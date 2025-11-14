#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/../common.sh"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Creating MinIO Credentials Secret ${NC}"
echo -e "${BLUE}========================================${NC}"

# Track if we started the port-forward
STARTED_PORT_FORWARD=false

# Check if port-forward is already running
if ! pgrep -f "port-forward.*myminio-hl.*9000:9000" > /dev/null; then
    echo -e "${YELLOW}Starting port-forward to MinIO service...${NC}"
    kubectl -n "${MINIO_TENANT_NAMESPACE}" port-forward svc/myminio-hl 9000:9000 > /dev/null 2>&1 &
    MINIO_PORT_FORWARD_PID=$!
    STARTED_PORT_FORWARD=true
    # Wait for port-forward to be ready
    sleep 5
else
    echo -e "${GREEN}✓ MinIO port-forward already running${NC}"
fi

# Cleanup function
cleanup() {
    if [ "$STARTED_PORT_FORWARD" = true ] && [ -n "$MINIO_PORT_FORWARD_PID" ]; then
        echo -e "${YELLOW}Stopping port-forward...${NC}"
        kill $MINIO_PORT_FORWARD_PID 2>/dev/null || true
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

echo -e "${YELLOW}Retrieving MinIO root credentials...${NC}"
MINIO_ACCESS_KEY=$(kubectl -n "${MINIO_TENANT_NAMESPACE}" get secret storage-user -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
MINIO_SECRET_KEY=$(kubectl -n "${MINIO_TENANT_NAMESPACE}" get secret storage-user -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)

echo -e "${YELLOW}Configuring MinIO client...${NC}"
# Check if mc is installed
if ! command -v mc &> /dev/null; then
    echo -e "${RED}ERROR: MinIO client (mc) is not installed${NC}"
    echo -e "${RED}Please install it from: https://github.com/minio/mc${NC}"
    exit 1
fi

mc alias set myminio https://localhost:9000 "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" --insecure

echo -e "${YELLOW}Creating MinIO service account for Gravitino...${NC}"
# Check if service account already exists
if mc admin user svcacct info myminio gravitino-svc --insecure &>/dev/null; then
    echo -e "${YELLOW}Service account 'gravitino-svc' already exists, removing it first...${NC}"
    mc admin user svcacct rm myminio gravitino-svc --insecure
fi

SVCACCT_OUTPUT=$(mc admin user svcacct add myminio console --name gravitino-svc --insecure 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create service account${NC}"
    echo -e "${RED}${SVCACCT_OUTPUT}${NC}"
    exit 1
fi

# Parse the output to get access key and secret key
GRAVITINO_S3_ACCESS_KEY=$(echo "$SVCACCT_OUTPUT" | grep "Access Key" | awk '{print $3}')
GRAVITINO_S3_SECRET_KEY=$(echo "$SVCACCT_OUTPUT" | grep "Secret Key" | awk '{print $3}')

if [ -z "$GRAVITINO_S3_ACCESS_KEY" ] || [ -z "$GRAVITINO_S3_SECRET_KEY" ]; then
    echo -e "${RED}Failed to parse service account credentials${NC}"
    echo -e "${RED}Output: ${SVCACCT_OUTPUT}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Service account created successfully${NC}"
echo -e "${GREEN}  Access Key: ${GRAVITINO_S3_ACCESS_KEY}${NC}"
echo -e "${GREEN}  Secret Key: [REDACTED]${NC}"
echo ""

echo -e "${YELLOW}Creating Kubernetes secret 'gravitino-minio-credentials' in ${GRAVITINO_NAMESPACE} namespace...${NC}"

# Delete existing secret if it exists
kubectl delete secret gravitino-minio-credentials -n "${GRAVITINO_NAMESPACE}" --ignore-not-found=true

# Create new secret
kubectl create secret generic gravitino-minio-credentials \
    -n "${GRAVITINO_NAMESPACE}" \
    --from-literal=access-key="${GRAVITINO_S3_ACCESS_KEY}" \
    --from-literal=secret-key="${GRAVITINO_S3_SECRET_KEY}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Kubernetes secret created successfully${NC}"
else
    echo -e "${RED}Failed to create Kubernetes secret${NC}"
    exit 1
fi
echo ""
