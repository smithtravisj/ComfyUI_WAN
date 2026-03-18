#!/usr/bin/env python3
"""
Programmatic deployment script for ComfyUI WAN 2.2 serverless endpoint

Usage:
    python deploy.py create --name "ComfyUI WAN 2.2" --gpu "NVIDIA RTX 4090"
    python deploy.py update ENDPOINT_ID --image ghcr.io/user/image:latest
    python deploy.py delete ENDPOINT_ID
    python deploy.py list
    python deploy.py info ENDPOINT_ID

Requirements:
    pip install requests python-dotenv
"""

import argparse
import json
import os
import sys
from typing import Dict, Optional
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: requests library not installed")
    print("Install with: pip install requests")
    sys.exit(1)

try:
    from dotenv import load_dotenv
except ImportError:
    print("WARNING: python-dotenv not installed")
    print("Install with: pip install python-dotenv")
    load_dotenv = lambda: None

# Load environment variables
load_dotenv()

# RunPod API configuration
RUNPOD_API_KEY = os.getenv("RUNPOD_API_KEY")
RUNPOD_API_URL = "https://api.runpod.io/graphql"


def check_api_key():
    """Verify RunPod API key is configured"""
    if not RUNPOD_API_KEY:
        print("ERROR: RUNPOD_API_KEY not set")
        print("Set in environment or .env file")
        print("Get API key from: https://www.runpod.io/console/user/settings")
        sys.exit(1)


def graphql_request(query: str, variables: Optional[Dict] = None) -> Dict:
    """Execute GraphQL request to RunPod API"""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {RUNPOD_API_KEY}"
    }

    payload = {
        "query": query,
        "variables": variables or {}
    }

    try:
        response = requests.post(
            RUNPOD_API_URL,
            json=payload,
            headers=headers,
            timeout=30
        )
        response.raise_for_status()
        data = response.json()

        if "errors" in data:
            print("ERROR: GraphQL errors:")
            for error in data["errors"]:
                print(f"  - {error.get('message', 'Unknown error')}")
            sys.exit(1)

        return data.get("data", {})

    except requests.RequestException as e:
        print(f"ERROR: API request failed: {e}")
        sys.exit(1)


def list_endpoints():
    """List all serverless endpoints"""
    query = """
    query {
      myself {
        serverlessDiscount {
          discountFactor
          type
        }
        serverlessTemplates {
          id
          name
          imageName
          dockerArgs
          containerDiskInGb
          volumeInGb
          volumeMountPath
          env
          scalerType
          scalerValue
          minWorkers
          maxWorkers
          gpuTypeIds
          networkVolumeId
        }
      }
    }
    """

    print("\n" + "=" * 70)
    print("RunPod Serverless Endpoints")
    print("=" * 70 + "\n")

    data = graphql_request(query)
    templates = data.get("myself", {}).get("serverlessTemplates", [])

    if not templates:
        print("No serverless endpoints found")
        return

    for template in templates:
        print(f"ID: {template['id']}")
        print(f"Name: {template['name']}")
        print(f"Image: {template['imageName']}")
        print(f"Workers: {template['minWorkers']}-{template['maxWorkers']}")
        print(f"GPU: {', '.join(template.get('gpuTypeIds', []))}")
        print()


def get_endpoint_info(endpoint_id: str):
    """Get detailed information about an endpoint"""
    query = """
    query ($id: String!) {
      serverlessTemplate(id: $id) {
        id
        name
        imageName
        dockerArgs
        containerDiskInGb
        volumeInGb
        volumeMountPath
        env
        scalerType
        scalerValue
        minWorkers
        maxWorkers
        idleTimeout
        executionTimeout
        gpuTypeIds
        networkVolumeId
      }
    }
    """

    print("\n" + "=" * 70)
    print("Endpoint Details")
    print("=" * 70 + "\n")

    data = graphql_request(query, {"id": endpoint_id})
    template = data.get("serverlessTemplate")

    if not template:
        print(f"Endpoint not found: {endpoint_id}")
        sys.exit(1)

    print(f"ID: {template['id']}")
    print(f"Name: {template['name']}")
    print(f"Image: {template['imageName']}")
    print(f"Container Disk: {template['containerDiskInGb']}GB")
    print(f"Volume: {template['volumeInGb']}GB at {template['volumeMountPath']}")
    print(f"Scaler: {template['scalerType']} ({template['scalerValue']})")
    print(f"Workers: {template['minWorkers']}-{template['maxWorkers']}")
    print(f"Timeouts: idle={template['idleTimeout']}s, execution={template['executionTimeout']}s")
    print(f"GPU: {', '.join(template.get('gpuTypeIds', []))}")
    print(f"Network Volume: {template.get('networkVolumeId', 'None')}")
    print()

    if template.get("env"):
        print("Environment Variables:")
        for env_var in template["env"]:
            key = env_var.get("key", "")
            # Mask sensitive values
            if any(secret in key.upper() for secret in ["KEY", "SECRET", "PASSWORD", "TOKEN"]):
                value = "***MASKED***"
            else:
                value = env_var.get("value", "")
            print(f"  {key}={value}")


def create_endpoint(
    name: str,
    image: str,
    gpu: str,
    network_volume_id: Optional[str] = None,
    template_file: Optional[str] = None
):
    """Create new serverless endpoint"""

    # Load template if provided
    if template_file:
        try:
            with open(template_file, 'r') as f:
                template = json.load(f)
        except Exception as e:
            print(f"ERROR: Failed to load template: {e}")
            sys.exit(1)
    else:
        # Use default template
        template = {
            "name": name,
            "dockerImage": image,
            "containerDiskInGb": 20,
            "volumeInGb": 100,
            "volumeMountPath": "/workspace",
            "minWorkers": 0,
            "maxWorkers": 3,
            "scalerType": "QUEUE_DELAY",
            "scalerValue": 5,
            "idleTimeout": 30,
            "executionTimeout": 900,
            "env": []
        }

    # Override with provided values
    template["name"] = name
    template["dockerImage"] = image
    if network_volume_id:
        template["networkVolumeId"] = network_volume_id

    # Map GPU name to ID
    gpu_mapping = {
        "NVIDIA RTX 4090": "NVIDIA GeForce RTX 4090",
        "RTX 4090": "NVIDIA GeForce RTX 4090",
        "4090": "NVIDIA GeForce RTX 4090",
        "A100": "NVIDIA A100 80GB PCIe",
        "A40": "NVIDIA A40",
    }
    gpu_id = gpu_mapping.get(gpu, gpu)

    mutation = """
    mutation ($input: CreateServerlessTemplateInput!) {
      createServerlessTemplate(input: $input) {
        id
        name
      }
    }
    """

    variables = {
        "input": {
            "name": template["name"],
            "imageName": template["dockerImage"],
            "dockerArgs": template.get("dockerArgs", ""),
            "containerDiskInGb": template["containerDiskInGb"],
            "volumeInGb": template["volumeInGb"],
            "volumeMountPath": template["volumeMountPath"],
            "env": template.get("env", []),
            "scalerType": template["scalerType"],
            "scalerValue": template["scalerValue"],
            "minWorkers": template["minWorkers"],
            "maxWorkers": template["maxWorkers"],
            "idleTimeout": template.get("idleTimeout", 30),
            "executionTimeout": template.get("executionTimeout", 900),
            "gpuTypeIds": [gpu_id],
            "networkVolumeId": template.get("networkVolumeId"),
        }
    }

    print("\n" + "=" * 70)
    print("Creating Serverless Endpoint")
    print("=" * 70 + "\n")

    print(f"Name: {template['name']}")
    print(f"Image: {template['dockerImage']}")
    print(f"GPU: {gpu_id}")
    print(f"Network Volume: {template.get('networkVolumeId', 'None')}")
    print()

    data = graphql_request(mutation, variables)
    result = data.get("createServerlessTemplate")

    if result:
        print(f"✓ Endpoint created successfully!")
        print(f"  ID: {result['id']}")
        print(f"  Name: {result['name']}")
        print()
        print(f"Endpoint URL: https://api.runpod.ai/v2/{result['id']}")
    else:
        print("✗ Failed to create endpoint")
        sys.exit(1)


def update_endpoint(endpoint_id: str, **kwargs):
    """Update existing serverless endpoint"""
    mutation = """
    mutation ($id: String!, $input: UpdateServerlessTemplateInput!) {
      updateServerlessTemplate(id: $id, input: $input) {
        id
        name
      }
    }
    """

    update_input = {}
    if kwargs.get("image"):
        update_input["imageName"] = kwargs["image"]
    if kwargs.get("min_workers") is not None:
        update_input["minWorkers"] = kwargs["min_workers"]
    if kwargs.get("max_workers") is not None:
        update_input["maxWorkers"] = kwargs["max_workers"]

    if not update_input:
        print("ERROR: No update parameters provided")
        sys.exit(1)

    variables = {
        "id": endpoint_id,
        "input": update_input
    }

    print("\n" + "=" * 70)
    print("Updating Serverless Endpoint")
    print("=" * 70 + "\n")

    print(f"Endpoint: {endpoint_id}")
    print(f"Updates: {json.dumps(update_input, indent=2)}")
    print()

    data = graphql_request(mutation, variables)
    result = data.get("updateServerlessTemplate")

    if result:
        print("✓ Endpoint updated successfully")
    else:
        print("✗ Failed to update endpoint")
        sys.exit(1)


def delete_endpoint(endpoint_id: str):
    """Delete serverless endpoint"""
    mutation = """
    mutation ($id: String!) {
      deleteServerlessTemplate(id: $id)
    }
    """

    print("\n" + "=" * 70)
    print("Deleting Serverless Endpoint")
    print("=" * 70 + "\n")

    print(f"Endpoint: {endpoint_id}")
    print()
    input("Press Enter to confirm deletion (Ctrl+C to cancel)...")

    data = graphql_request(mutation, {"id": endpoint_id})

    if data.get("deleteServerlessTemplate"):
        print("✓ Endpoint deleted successfully")
    else:
        print("✗ Failed to delete endpoint")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Deploy ComfyUI WAN 2.2 to RunPod serverless"
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # List command
    subparsers.add_parser("list", help="List all serverless endpoints")

    # Info command
    info_parser = subparsers.add_parser("info", help="Get endpoint details")
    info_parser.add_argument("endpoint_id", help="Endpoint ID")

    # Create command
    create_parser = subparsers.add_parser("create", help="Create new endpoint")
    create_parser.add_argument("--name", required=True, help="Endpoint name")
    create_parser.add_argument("--image", required=True, help="Docker image URL")
    create_parser.add_argument("--gpu", default="NVIDIA RTX 4090", help="GPU type")
    create_parser.add_argument("--network-volume", help="Network volume ID")
    create_parser.add_argument("--template", help="Path to template JSON file")

    # Update command
    update_parser = subparsers.add_parser("update", help="Update endpoint")
    update_parser.add_argument("endpoint_id", help="Endpoint ID")
    update_parser.add_argument("--image", help="New Docker image")
    update_parser.add_argument("--min-workers", type=int, help="Minimum workers")
    update_parser.add_argument("--max-workers", type=int, help="Maximum workers")

    # Delete command
    delete_parser = subparsers.add_parser("delete", help="Delete endpoint")
    delete_parser.add_argument("endpoint_id", help="Endpoint ID")

    args = parser.parse_args()

    # Check API key for all commands
    check_api_key()

    # Execute command
    if args.command == "list":
        list_endpoints()

    elif args.command == "info":
        get_endpoint_info(args.endpoint_id)

    elif args.command == "create":
        create_endpoint(
            name=args.name,
            image=args.image,
            gpu=args.gpu,
            network_volume_id=args.network_volume,
            template_file=args.template
        )

    elif args.command == "update":
        update_endpoint(
            endpoint_id=args.endpoint_id,
            image=args.image,
            min_workers=args.min_workers,
            max_workers=args.max_workers
        )

    elif args.command == "delete":
        delete_endpoint(args.endpoint_id)


if __name__ == "__main__":
    main()
