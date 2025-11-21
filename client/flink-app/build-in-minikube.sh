#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if minikube is available
if ! command -v minikube &> /dev/null; then
    echo "Error: minikube binary not found. Please install minikube."
    exit 1
fi

# Image name and tag
IMAGE_NAME="flink-sql-runner-gravitino:latest"

echo ""
echo "Building Flink image with Gravitino connector inside minikube..."
echo "Image: ${IMAGE_NAME}"
echo ""

# Build the image directly inside minikube
cd "${SCRIPT_DIR}"
minikube image build -t "${IMAGE_NAME}" .

echo ""
echo "✓ Image built successfully inside minikube!"
echo ""
echo "Image name: ${IMAGE_NAME}"
echo ""
echo "You can now deploy the Flink session cluster with:"
echo "  kubectl apply -f ${SCRIPT_DIR}/flink-session.yaml"
echo ""
echo "To verify the image is available in minikube:"
echo "  minikube image ls | grep flink-sql-runner-gravitino"
echo ""
