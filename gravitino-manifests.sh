#!/bin/bash

set -e

# Get the repo root directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
GRAVITINO_TAG="${1}"
NAMESPACE="${2:-metadata}"  # Use second argument or default to 'metadata'

if [ -z "${GRAVITINO_TAG}" ]; then
    echo "Usage: $0 <gravitino-tag> [namespace]"
    echo "  gravitino-tag: Git tag/branch to checkout in the Gravitino submodule"
    echo "  namespace: Kubernetes namespace (default: metadata)"
    exit 1
fi

GRAVITINO_SUBMODULE_PATH="${REPO_ROOT}/gravitino"
CHARTS_PATH="${GRAVITINO_SUBMODULE_PATH}/dev/charts"
OUTPUT_DIR="${REPO_ROOT}/manifests/gravitino"
RELEASE_NAME="gravitino"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Gravitino Helm chart extraction...${NC}"
echo -e "${YELLOW}Gravitino tag: ${GRAVITINO_TAG}${NC}"
echo -e "${YELLOW}Target namespace: ${NAMESPACE}${NC}"

# Check if gravitino submodule exists
if [ ! -d "${GRAVITINO_SUBMODULE_PATH}" ]; then
    echo -e "${RED}Error: Gravitino submodule not found at ${GRAVITINO_SUBMODULE_PATH}${NC}"
    echo "Please add the submodule first: git submodule add https://github.com/apache/gravitino.git"
    exit 1
fi

# Initialize and update submodule if needed
echo -e "${YELLOW}Updating Gravitino submodule...${NC}"
git submodule update --init --recursive

# Checkout the specified tag in the submodule
echo -e "${YELLOW}Checking out tag ${GRAVITINO_TAG} in Gravitino submodule...${NC}"
cd "${GRAVITINO_SUBMODULE_PATH}"
git checkout "${GRAVITINO_TAG}"
cd "${REPO_ROOT}"

# Navigate to charts directory
cd "${CHARTS_PATH}"

# Update helm dependencies
echo -e "${YELLOW}Updating Helm dependencies...${NC}"
helm dependency update gravitino

# Package the helm chart
echo -e "${YELLOW}Packaging Helm chart...${NC}"
helm package gravitino

# Get the packaged chart name and extract version
CHART_PACKAGE=$(ls gravitino-*.tgz | head -n 1)

if [ -z "${CHART_PACKAGE}" ]; then
    echo -e "${RED}Error: Failed to find packaged chart${NC}"
    exit 1
fi

# Extract version from chart package filename (e.g., gravitino-1.1.0.tgz -> 1.1.0)
CHART_VERSION=$(echo "${CHART_PACKAGE}" | sed 's/gravitino-\(.*\)\.tgz/\1/')

echo -e "${GREEN}Chart packaged: ${CHART_PACKAGE} (version: ${CHART_VERSION})${NC}"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Generate Kubernetes manifests using helm template
echo -e "${YELLOW}Generating Kubernetes manifests...${NC}"
helm template ${RELEASE_NAME} ./${CHART_PACKAGE} \
    --namespace ${NAMESPACE} \
    --set mysql.enabled=true \
    > "${OUTPUT_DIR}/gravitino-manifests-${CHART_VERSION}.yaml"

cd "${REPO_ROOT}"

echo -e "${GREEN}✓ Extraction complete!${NC}"
echo -e "Manifests saved to: ${OUTPUT_DIR}/gravitino-manifests-${CHART_VERSION}.yaml"
echo -e "\nTo apply these manifests, run:"
echo -e "  kubectl create namespace ${NAMESPACE}"
echo -e "  kubectl apply -f manifests/gravitino/gravitino-manifests-${CHART_VERSION}.yaml"