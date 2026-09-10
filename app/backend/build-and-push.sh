#!/usr/bin/env bash
set -euo pipefail

# Run from app/backend. Usage: ./build-and-push.sh <ecr_repository_url> <aws_region>
ECR_REPOSITORY="${1:?Usage: ./build-and-push.sh <ecr_repository_url> <aws_region>}"
REGION="${2:?Usage: ./build-and-push.sh <ecr_repository_url> <aws_region>}"

aws ecr get-login-password --region "$REGION" | podman login --username AWS --password-stdin "$ECR_REPOSITORY"
podman build -t "${ECR_REPOSITORY}:latest" .
podman push "${ECR_REPOSITORY}:latest"
