#!/usr/bin/env python3
"""
Test script for ComfyUI WAN 2.2 serverless handler

Usage:
    python test_handler.py [--local|--remote] [--workflow WORKFLOW_FILE]

Examples:
    # Test local Docker container
    python test_handler.py --local

    # Test remote RunPod endpoint
    python test_handler.py --remote --endpoint https://api.runpod.ai/v2/YOUR_ENDPOINT_ID

    # Test with custom workflow
    python test_handler.py --local --workflow examples/t2v_workflow.json
"""

import argparse
import json
import time
import sys
from pathlib import Path
from typing import Dict, Optional

try:
    import requests
except ImportError:
    print("ERROR: requests library not installed")
    print("Install with: pip install requests")
    sys.exit(1)


def load_workflow(workflow_path: str) -> Dict:
    """Load workflow JSON from file"""
    try:
        with open(workflow_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"ERROR: Workflow file not found: {workflow_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON in workflow file: {e}")
        sys.exit(1)


def test_local_handler(workflow: Dict, timeout: int = 300) -> Dict:
    """Test handler in local Docker container"""
    print("\n" + "=" * 70)
    print("Testing Local Docker Handler")
    print("=" * 70 + "\n")

    # Simulate RunPod job structure
    job = {
        "id": f"test_{int(time.time())}",
        "input": {
            "workflow": workflow
        }
    }

    print(f"Job ID: {job['id']}")
    print(f"Workflow nodes: {len(workflow)}")
    print(f"Timeout: {timeout}s")
    print()

    # Import handler module
    try:
        sys.path.insert(0, str(Path(__file__).parent))
        import handler
    except ImportError as e:
        print(f"ERROR: Failed to import handler: {e}")
        print("Ensure handler.py is in the same directory")
        sys.exit(1)

    # Run handler
    print("Executing handler...")
    start_time = time.time()

    try:
        result = handler.handler(job)
        duration = time.time() - start_time

        print(f"\n✓ Handler completed in {duration:.1f}s")
        return result

    except Exception as e:
        duration = time.time() - start_time
        print(f"\n✗ Handler failed after {duration:.1f}s")
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


def test_remote_endpoint(workflow: Dict, endpoint_url: str, api_key: Optional[str] = None, timeout: int = 900) -> Dict:
    """Test RunPod serverless endpoint"""
    print("\n" + "=" * 70)
    print("Testing Remote RunPod Endpoint")
    print("=" * 70 + "\n")

    print(f"Endpoint: {endpoint_url}")
    print(f"Workflow nodes: {len(workflow)}")
    print(f"Timeout: {timeout}s")
    print()

    # Prepare request
    headers = {
        "Content-Type": "application/json"
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    payload = {
        "input": {
            "workflow": workflow
        }
    }

    # Submit job
    print("Submitting job...")
    submit_start = time.time()

    try:
        response = requests.post(
            f"{endpoint_url}/run",
            json=payload,
            headers=headers,
            timeout=30
        )
        response.raise_for_status()
        job_data = response.json()

        if "id" not in job_data:
            print(f"ERROR: Invalid response from endpoint: {job_data}")
            sys.exit(1)

        job_id = job_data["id"]
        submit_duration = time.time() - submit_start

        print(f"✓ Job submitted in {submit_duration:.1f}s")
        print(f"Job ID: {job_id}")
        print()

    except requests.RequestException as e:
        print(f"ERROR: Failed to submit job: {e}")
        sys.exit(1)

    # Poll for results
    print("Waiting for job completion...")
    poll_start = time.time()
    poll_count = 0
    max_polls = timeout // 5  # Poll every 5 seconds

    while poll_count < max_polls:
        try:
            response = requests.get(
                f"{endpoint_url}/status/{job_id}",
                headers=headers,
                timeout=10
            )
            response.raise_for_status()
            status_data = response.json()

            status = status_data.get("status")
            poll_count += 1
            elapsed = time.time() - poll_start

            if status == "COMPLETED":
                print(f"\n✓ Job completed in {elapsed:.1f}s")
                return status_data.get("output", {})

            elif status == "FAILED":
                print(f"\n✗ Job failed after {elapsed:.1f}s")
                error = status_data.get("error", "Unknown error")
                print(f"Error: {error}")
                sys.exit(1)

            elif status in ["IN_QUEUE", "IN_PROGRESS"]:
                print(f"[{elapsed:.0f}s] Status: {status}", end="\r")
                time.sleep(5)

            else:
                print(f"\nWarning: Unknown status: {status}")
                time.sleep(5)

        except requests.RequestException as e:
            print(f"\nWarning: Poll failed: {e}")
            time.sleep(5)

    print(f"\n✗ Job timed out after {timeout}s")
    sys.exit(1)


def print_results(result: Dict):
    """Print handler results in formatted way"""
    print("\n" + "=" * 70)
    print("Results")
    print("=" * 70 + "\n")

    if result.get("error"):
        print(f"❌ Error: {result['error']}")
        if "traceback" in result:
            print("\nTraceback:")
            print(result["traceback"])
        return

    if result.get("success"):
        print("✅ Success!")
        print()

        # Timing
        if "execution_time" in result:
            print(f"Execution time: {result['execution_time']:.1f}s")
        if "total_duration" in result:
            print(f"Total duration: {result['total_duration']:.1f}s")
        print()

        # Outputs
        outputs = result.get("outputs", [])
        print(f"Outputs: {len(outputs)}")
        for i, output in enumerate(outputs, 1):
            print(f"\n{i}. {output.get('filename', 'unknown')}")
            print(f"   URL: {output.get('url', 'N/A')}")
            print(f"   Size: {output.get('size', 0) / 1024 / 1024:.2f}MB")
            print(f"   Type: {output.get('type', 'unknown')}")

        # Message
        if "message" in result:
            print(f"\n{result['message']}")
    else:
        print("⚠️  Unknown result format:")
        print(json.dumps(result, indent=2))


def create_simple_workflow() -> Dict:
    """Create a minimal test workflow for validation"""
    return {
        "1": {
            "inputs": {
                "text": "A cat playing piano",
                "clip": ["2", 0]
            },
            "class_type": "CLIPTextEncode"
        },
        "2": {
            "inputs": {
                "clip_name1": "umt5-xxl-encoder-Q5_K_S.gguf",
                "clip_name2": "umt5-xxl-encoder-Q5_K_S.gguf",
                "type": "gguf"
            },
            "class_type": "DualCLIPLoader"
        }
    }


def main():
    parser = argparse.ArgumentParser(
        description="Test ComfyUI WAN 2.2 serverless handler"
    )

    # Execution mode
    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument(
        "--local",
        action="store_true",
        help="Test local Docker container"
    )
    mode_group.add_argument(
        "--remote",
        action="store_true",
        help="Test remote RunPod endpoint"
    )

    # Workflow
    parser.add_argument(
        "--workflow",
        type=str,
        help="Path to workflow JSON file (default: minimal test workflow)"
    )

    # Remote endpoint configuration
    parser.add_argument(
        "--endpoint",
        type=str,
        help="RunPod endpoint URL (required for --remote)"
    )
    parser.add_argument(
        "--api-key",
        type=str,
        help="RunPod API key (optional)"
    )

    # Timeouts
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Execution timeout in seconds (default: 300)"
    )

    args = parser.parse_args()

    # Validate arguments
    if args.remote and not args.endpoint:
        parser.error("--remote requires --endpoint")

    # Load workflow
    if args.workflow:
        workflow = load_workflow(args.workflow)
        print(f"Loaded workflow from: {args.workflow}")
    else:
        workflow = create_simple_workflow()
        print("Using minimal test workflow")

    # Run test
    if args.local:
        result = test_local_handler(workflow, timeout=args.timeout)
    else:
        result = test_remote_endpoint(
            workflow,
            args.endpoint,
            api_key=args.api_key,
            timeout=args.timeout
        )

    # Print results
    print_results(result)


if __name__ == "__main__":
    main()
