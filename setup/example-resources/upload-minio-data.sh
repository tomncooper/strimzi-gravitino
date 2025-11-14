#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/../common.sh"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Uploading Data to MinIO ${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if port-forward is already running
if ! pgrep -f "port-forward.*myminio-hl.*9000:9000" > /dev/null; then
    echo -e "${YELLOW}Starting port-forward to MinIO service...${NC}"
    kubectl -n "${MINIO_TENANT_NAMESPACE}" port-forward svc/myminio-hl 9000:9000 > /dev/null 2>&1 &
    MINIO_PORT_FORWARD_PID=$!
    # Wait for port-forward to be ready
    sleep 5
else
    echo -e "${GREEN}✓ MinIO port-forward already running${NC}"
    MINIO_PORT_FORWARD_PID=$(pgrep -f "port-forward.*myminio-hl.*9000:9000")
fi

echo -e "${YELLOW}Retrieving MinIO admin credentials...${NC}"
MINIO_ACCESS_KEY=$(kubectl -n "${GRAVITINO_NAMESPACE}" get secret gravitino-minio-credentials -o jsonpath='{.data.access-key}' | base64 -d)
MINIO_SECRET_KEY=$(kubectl -n "${GRAVITINO_NAMESPACE}" get secret gravitino-minio-credentials -o jsonpath='{.data.secret-key}' | base64 -d)

BUCKET="product-csvs"
SUBFOLDER="schema/product-data"
OBJECT="productInventory.csv"
FILE="${SCRIPT_DIR}/../data/productInventory.csv"

echo -e "${YELLOW}Configuring MinIO client...${NC}"
# Check if mc is installed
if ! command -v mc &> /dev/null; then
    echo -e "${RED}ERROR: MinIO client (mc) is not installed${NC}"
    echo -e "${RED}Please install it from: https://github.com/minio/mc${NC}"
    exit 1
fi

mc alias set myminio https://localhost:9000 "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" --insecure

MINIO_FILEPATH="myminio/${BUCKET}/${SUBFOLDER}/${OBJECT}"

echo -e "${YELLOW}Checking if productInventory.csv already exists...${NC}"
if mc stat "${MINIO_FILEPATH}" --insecure &>/dev/null; then
    echo -e "${GREEN}✓ productInventory.csv already exists in bucket${NC}"
else
    echo -e "${YELLOW}Uploading productInventory.csv to ${BUCKET}...${NC}"
    mc cp "${FILE}" "${MINIO_FILEPATH}" --insecure
    echo -e "${GREEN}✓ Data uploaded successfully${NC}"
fi
echo ""
