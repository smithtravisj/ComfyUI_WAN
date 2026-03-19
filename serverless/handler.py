#!/usr/bin/env python3
"""
RunPod Serverless Handler for ComfyUI WAN 2.2
Optimized for burst workloads with S3 upload integration

Architecture:
- Direct execution via PromptExecutor.execute_async() (bypasses queue)
- Network volume for models and venv (/workspace)
- S3/R2 upload for outputs
- RAM_PRESSURE cache for aggressive memory management
- Global executor reuse for warm starts
"""

import runpod
import asyncio
import json
import os
import sys
import time
import uuid
import glob
import traceback
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple

# S3/R2 client (optional)
try:
    import boto3
    from botocore.config import Config
    S3_AVAILABLE = True
except ImportError:
    print("WARNING: boto3 not available. S3 uploads disabled.")
    S3_AVAILABLE = False

# Add ComfyUI to path and change to ComfyUI directory
COMFYUI_DIR = Path("/comfyui")
sys.path.insert(0, str(COMFYUI_DIR))
os.chdir(COMFYUI_DIR)

# Temporarily disable custom_nodes by renaming directory during import
# This prevents missing dependency errors from network volume custom nodes
CUSTOM_NODES_DIR = COMFYUI_DIR / "custom_nodes"
CUSTOM_NODES_DISABLED = COMFYUI_DIR / "custom_nodes.disabled"
custom_nodes_temporarily_disabled = False

if CUSTOM_NODES_DIR.exists() and CUSTOM_NODES_DIR.is_symlink():
    try:
        CUSTOM_NODES_DIR.rename(CUSTOM_NODES_DISABLED)
        custom_nodes_temporarily_disabled = True
        print("ℹ Temporarily disabled custom_nodes for clean import")
    except Exception as e:
        print(f"WARNING: Could not disable custom_nodes: {e}")

# Activate network volume venv
VENV_PATH = Path("/workspace/venv")
if VENV_PATH.exists():
    print(f"Activating venv from {VENV_PATH}")
    site_packages = VENV_PATH / "lib" / "python3.11" / "site-packages"
    if site_packages.exists():
        sys.path.insert(0, str(site_packages))
    else:
        # Fallback: try to find site-packages
        for sp in VENV_PATH.glob("lib/python*/site-packages"):
            sys.path.insert(0, str(sp))
            break
else:
    print(f"WARNING: venv not found at {VENV_PATH}")

# Import ComfyUI modules (after venv activation)
try:
    import folder_paths
    import execution
    import nodes
    from server import PromptServer
    import comfy.model_management
    COMFYUI_AVAILABLE = True
    print("✓ ComfyUI core modules imported successfully")
except ImportError as e:
    print(f"ERROR: Failed to import ComfyUI modules: {e}")
    print(f"ERROR: This may be caused by a custom node with missing dependencies")
    print(f"ERROR: Check custom_nodes directory and disable problematic nodes")
    COMFYUI_AVAILABLE = False
    # Store the error for later reporting
    COMFYUI_IMPORT_ERROR = str(e)
finally:
    # Re-enable custom_nodes after core import
    if custom_nodes_temporarily_disabled and CUSTOM_NODES_DISABLED.exists():
        try:
            CUSTOM_NODES_DISABLED.rename(CUSTOM_NODES_DIR)
            print("✓ Re-enabled custom_nodes directory")
        except Exception as e:
            print(f"WARNING: Could not re-enable custom_nodes: {e}")

# Configure folder paths to use network volume
if COMFYUI_AVAILABLE:
    folder_paths.models_dir = "/workspace/models"
    folder_paths.output_directory = "/workspace/output"
    folder_paths.temp_directory = "/workspace/temp"
    folder_paths.input_directory = "/comfyui/input"

# =============================================================================
# S3/R2 Configuration
# =============================================================================

s3_client = None
S3_BUCKET = os.getenv('R2_BUCKET') or os.getenv('S3_BUCKET', 'comfyui-outputs')
S3_PUBLIC_URL = os.getenv('R2_PUBLIC_URL') or os.getenv('S3_PUBLIC_URL')

def init_s3_client():
    """Initialize S3-compatible client for output uploads"""
    global s3_client

    if not S3_AVAILABLE:
        return None

    endpoint = os.getenv('R2_ENDPOINT') or os.getenv('S3_ENDPOINT')
    access_key = os.getenv('R2_ACCESS_KEY') or os.getenv('AWS_ACCESS_KEY_ID')
    secret_key = os.getenv('R2_SECRET_KEY') or os.getenv('AWS_SECRET_ACCESS_KEY')

    if not all([endpoint, access_key, secret_key]):
        print("INFO: S3/R2 credentials not configured. Outputs will be stored locally only.")
        return None

    s3_config = Config(
        signature_version='s3v4',
        retries={'max_attempts': 3, 'mode': 'adaptive'}
    )

    try:
        s3_client = boto3.client(
            's3',
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            config=s3_config
        )
        print(f"✓ S3/R2 client initialized (endpoint: {endpoint})")
        return s3_client
    except Exception as e:
        print(f"WARNING: Failed to initialize S3 client: {e}")
        return None

# =============================================================================
# ComfyUI Initialization
# =============================================================================

# Global executor (reused across requests for warm starts)
global_executor = None
global_server = None

async def init_comfyui():
    """Initialize ComfyUI components (called once on cold start)"""
    global global_executor, global_server

    if not COMFYUI_AVAILABLE:
        raise RuntimeError("ComfyUI modules not available")

    print("=" * 70)
    print("Initializing ComfyUI...")
    print("=" * 70)

    # Create event loop if needed
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    # Create minimal server instance (no web server needed)
    global_server = PromptServer(loop)
    global_server.client_id = None  # No websocket connections in serverless

    # Initialize custom nodes
    print("Loading custom nodes...")
    start_time = time.time()
    await nodes.init_extra_nodes(
        init_custom_nodes=True,
        init_builtin_extra_nodes=True
    )
    print(f"✓ Custom nodes loaded ({time.time() - start_time:.1f}s)")

    # Initialize executor with RAM_PRESSURE cache for aggressive memory management
    cache_type_str = os.getenv('CACHE_TYPE', 'RAM_PRESSURE')
    cache_ram = float(os.getenv('CACHE_RAM', '16.0'))  # 16GB RAM pressure threshold

    cache_type_map = {
        'RAM_PRESSURE': execution.CacheType.RAM_PRESSURE,
        'LRU': execution.CacheType.LRU,
        'CLASSIC': execution.CacheType.CLASSIC,
        'NONE': execution.CacheType.NONE,
    }
    cache_type = cache_type_map.get(cache_type_str, execution.CacheType.RAM_PRESSURE)

    global_executor = execution.PromptExecutor(
        global_server,
        cache_type=cache_type,
        cache_args={"ram": cache_ram} if cache_type == execution.CacheType.RAM_PRESSURE else None
    )

    print(f"✓ Executor initialized (cache: {cache_type_str}, RAM threshold: {cache_ram}GB)")
    print("=" * 70)
    print("ComfyUI initialization complete")
    print("=" * 70)

    return global_executor, global_server

# =============================================================================
# Workflow Execution
# =============================================================================

async def validate_workflow(prompt: Dict) -> Tuple[bool, Optional[str]]:
    """Validate workflow before execution"""
    try:
        validated = {}
        for node_id in prompt:
            result = execution.validate_inputs(
                prompt,
                node_id,
                validated
            )
            if result[0] is False:
                error_msg = result[1] if len(result) > 1 else "Unknown validation error"
                return False, f"Validation failed for node {node_id}: {error_msg}"
        return True, None
    except Exception as e:
        return False, f"Validation error: {str(e)}"

async def execute_workflow(
    prompt: Dict,
    prompt_id: str,
    executor: Any,  # execution.PromptExecutor when available
    server: Any  # PromptServer when available
) -> Tuple[bool, Dict]:
    """Execute ComfyUI workflow without queue system"""
    try:
        print(f"Executing workflow (prompt_id: {prompt_id})")

        # Validate first
        valid, error = await validate_workflow(prompt)
        if not valid:
            return False, {"error": error}

        # Execute directly using async executor (bypasses queue!)
        start_time = time.time()
        await executor.execute(
            prompt=prompt,
            prompt_id=prompt_id,
            extra_data={},
            execute_outputs=[]
        )
        execution_time = time.time() - start_time

        # Check execution success
        if not executor.success:
            error_msg = "Execution failed"
            if hasattr(executor, 'status_messages') and executor.status_messages:
                error_msg += f": {executor.status_messages[-1]}"
            return False, {
                "error": error_msg,
                "execution_time": execution_time
            }

        print(f"✓ Workflow executed successfully ({execution_time:.1f}s)")
        return True, {
            "execution_time": execution_time,
            "success": True
        }

    except Exception as e:
        return False, {
            "error": str(e),
            "traceback": traceback.format_exc()
        }

# =============================================================================
# Output Handling
# =============================================================================

def find_output_files(prompt_id: str, output_dir: str = "/workspace/output") -> List[Path]:
    """Find generated output files for this prompt"""
    output_path = Path(output_dir)

    if not output_path.exists():
        print(f"WARNING: Output directory {output_dir} does not exist")
        return []

    # Look for files modified in the last 5 minutes
    cutoff_time = time.time() - 300

    output_files = []
    patterns = ['*.mp4', '*.avi', '*.mov', '*.webm', '*.png', '*.jpg', '*.jpeg', '*.webp', '*.gif']

    for pattern in patterns:
        for file_path in output_path.rglob(pattern):
            try:
                if file_path.stat().st_mtime > cutoff_time:
                    output_files.append(file_path)
            except (OSError, PermissionError) as e:
                print(f"WARNING: Could not stat file {file_path}: {e}")
                continue

    # Sort by modification time (most recent first)
    output_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    return output_files

def get_content_type(file_path: Path) -> str:
    """Get MIME type for file"""
    ext = file_path.suffix.lower()
    content_types = {
        '.mp4': 'video/mp4',
        '.avi': 'video/x-msvideo',
        '.mov': 'video/quicktime',
        '.webm': 'video/webm',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.webp': 'image/webp',
        '.gif': 'image/gif'
    }
    return content_types.get(ext, 'application/octet-stream')

def upload_to_s3(file_path: Path, prompt_id: str) -> Optional[str]:
    """Upload file to S3/R2 and return public URL"""
    if not s3_client:
        return None

    try:
        # Generate S3 key: prompt_id/filename
        s3_key = f"{prompt_id}/{file_path.name}"

        print(f"Uploading {file_path.name} to S3...")

        # Upload file
        s3_client.upload_file(
            str(file_path),
            S3_BUCKET,
            s3_key,
            ExtraArgs={'ContentType': get_content_type(file_path)}
        )

        # Return public URL
        if S3_PUBLIC_URL:
            url = f"{S3_PUBLIC_URL.rstrip('/')}/{s3_key}"
        else:
            # Use endpoint URL as fallback
            endpoint = s3_client.meta.endpoint_url
            url = f"{endpoint.rstrip('/')}/{S3_BUCKET}/{s3_key}"

        print(f"✓ Uploaded: {url}")
        return url

    except Exception as e:
        print(f"ERROR: S3 upload failed for {file_path}: {e}")
        traceback.print_exc()
        return None

def cleanup_outputs(output_files: List[Path]):
    """Clean up generated output files after upload"""
    cleanup_enabled = os.getenv('CLEANUP_OUTPUTS', 'true').lower() == 'true'

    if not cleanup_enabled:
        print("Output cleanup disabled")
        return

    for file_path in output_files:
        try:
            if file_path.exists():
                file_path.unlink()
                print(f"✓ Cleaned up: {file_path.name}")
        except Exception as e:
            print(f"WARNING: Failed to clean up {file_path}: {e}")

# =============================================================================
# Main Handler
# =============================================================================

async def handler_async(job: Dict) -> Dict:
    """Main async handler function"""
    job_id = job['id']
    job_input = job.get('input', {})

    print("\n" + "=" * 70)
    print(f"Processing job: {job_id}")
    print("=" * 70)

    start_time = time.time()

    # Check if ComfyUI is available
    if not COMFYUI_AVAILABLE:
        error_details = globals().get('COMFYUI_IMPORT_ERROR', 'Unknown import error')
        return {
            "error": f"ComfyUI modules failed to import: {error_details}",
            "details": "Check container logs. This may be caused by custom nodes with missing dependencies.",
            "duration": time.time() - start_time
        }

    try:
        # Parse workflow
        workflow = job_input.get('workflow')
        if not workflow:
            return {
                "error": "Missing 'workflow' in input",
                "duration": time.time() - start_time
            }

        # Parse workflow JSON if string
        if isinstance(workflow, str):
            try:
                workflow = json.loads(workflow)
            except json.JSONDecodeError as e:
                return {
                    "error": f"Invalid workflow JSON: {str(e)}",
                    "duration": time.time() - start_time
                }

        # Generate prompt ID
        prompt_id = f"{job_id}_{int(time.time())}"

        # Execute workflow
        print(f"\nExecuting workflow...")
        success, result = await execute_workflow(workflow, prompt_id, global_executor, global_server)

        if not success:
            return {
                "error": result.get("error", "Unknown execution error"),
                "details": result,
                "duration": time.time() - start_time
            }

        execution_time = result.get("execution_time", 0)

        # Find output files
        print(f"\nScanning for output files...")
        output_files = find_output_files(prompt_id)
        print(f"Found {len(output_files)} output files")

        # Upload to S3
        uploaded_urls = []
        if s3_client and output_files:
            print(f"\nUploading to S3...")
            for file_path in output_files:
                url = upload_to_s3(file_path, prompt_id)
                if url:
                    uploaded_urls.append({
                        "filename": file_path.name,
                        "url": url,
                        "size": file_path.stat().st_size,
                        "type": get_content_type(file_path)
                    })

        # Clean up local files
        if uploaded_urls:
            cleanup_outputs(output_files)

        # Explicit memory cleanup
        try:
            comfy.model_management.cleanup_models()
            comfy.model_management.soft_empty_cache()
        except Exception as e:
            print(f"WARNING: Memory cleanup failed: {e}")

        duration = time.time() - start_time

        print("\n" + "=" * 70)
        print(f"✓ Job completed successfully")
        print(f"  Execution: {execution_time:.1f}s")
        print(f"  Total: {duration:.1f}s")
        print(f"  Outputs: {len(uploaded_urls)}")
        print("=" * 70)

        return {
            "success": True,
            "prompt_id": prompt_id,
            "outputs": uploaded_urls,
            "execution_time": execution_time,
            "total_duration": duration,
            "message": f"Generated {len(uploaded_urls)} outputs"
        }

    except Exception as e:
        duration = time.time() - start_time
        error_msg = str(e)
        error_trace = traceback.format_exc()

        print("\n" + "=" * 70)
        print(f"✗ Job failed: {error_msg}")
        print("=" * 70)
        print(error_trace)

        return {
            "error": error_msg,
            "traceback": error_trace,
            "duration": duration
        }

async def handler(job: Dict) -> Dict:
    """Async handler for RunPod serverless (RunPod supports async handlers)"""
    return await handler_async(job)

# =============================================================================
# Startup
# =============================================================================

if __name__ == "__main__":
    print("\n" + "=" * 70)
    print("ComfyUI WAN 2.2 Serverless Handler")
    print("=" * 70)
    print(f"ComfyUI directory: {COMFYUI_DIR}")
    print(f"Models directory: {folder_paths.models_dir if COMFYUI_AVAILABLE else 'N/A'}")
    print(f"Output directory: {folder_paths.output_directory if COMFYUI_AVAILABLE else 'N/A'}")
    print(f"Venv path: {VENV_PATH}")
    print("=" * 70)

    # Initialize S3 client
    init_s3_client()

    # Initialize ComfyUI on startup
    if COMFYUI_AVAILABLE:
        print("\nInitializing ComfyUI...")
        asyncio.run(init_comfyui())

        # Optional: Preload models for faster cold starts
        warmup_enabled = os.getenv('WARMUP_MODELS', 'true').lower() == 'true'
        if warmup_enabled:
            try:
                print("\n" + "=" * 70)
                print("Running warmup...")
                print("=" * 70)
                import warmup
                asyncio.run(warmup.warmup_models())
            except ImportError:
                print("WARNING: warmup.py not found, skipping model preload")
            except Exception as e:
                print(f"WARNING: Warmup failed (non-fatal): {e}")
    else:
        print("\nERROR: ComfyUI not available. Handler will fail.")

    # Start RunPod serverless
    print("\n" + "=" * 70)
    print("Handler ready, waiting for jobs...")
    print("=" * 70 + "\n")

    runpod.serverless.start({"handler": handler})
