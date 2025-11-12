#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/common.sh"

# Setup Gravitino
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up Gravitino ${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}Checking that Gravitino is ready...${NC}"
kubectl -n "${GRAVITINO_NAMESPACE}" wait --for=condition=available deployment gravitino --timeout=300s

echo -e "${GREEN}✓ Gravitino is ready${NC}"
echo ""

# Check if port-forward is already running
if ! pgrep -f "port-forward.*gravitino.*8090:8090" > /dev/null; then
    echo -e "${YELLOW}Starting port-forward to Gravitino service...${NC}"
    kubectl -n "${GRAVITINO_NAMESPACE}" port-forward svc/gravitino 8090:8090 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    # Wait for port-forward to be ready
    sleep 5
else
    echo -e "${GREEN}✓ Gravitino port-forward already running${NC}"
    PORT_FORWARD_PID=$(pgrep -f "port-forward.*gravitino.*8090:8090")
fi

# Check if metalake exists
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    http://localhost:8090/api/metalakes/${METALAKE} 2>/dev/null | grep -q "NoSuchMetalakeException"; then
    echo -e "${YELLOW}Creating metalake...${NC}"
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
      -H "Content-Type: application/json" -d '{
        "name":"'"${METALAKE}"'",
        "comment":"This metalake holds all the demo system metadata",
        "properties":{}
    }' http://localhost:8090/api/metalakes
    echo ""
else
    echo -e "${GREEN}✓ Metalake already exists${NC}"
fi
echo ""

# Setup Kafka topics and catalog
echo -e "${YELLOW}Setting up Kafka topics and catalog...${NC}"
${SCRIPT_DIR}/example-resources/setup-kafka.sh
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up MinIO Tenant (S3 Storage) ${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if MinIO tenant already exists
if kubectl -n "${MINIO_TENANT_NAMESPACE}" get tenants.minio.min.io myminio &>/dev/null; then
    echo -e "${GREEN}✓ MinIO Tenant already exists${NC}"
else
    kubectl kustomize ${SCRIPT_DIR}/minio/tenant | kubectl apply -f -
fi

echo -e "${YELLOW}Waiting for MinIO Tenant to be ready...${NC}"
kubectl -n "${MINIO_TENANT_NAMESPACE}" wait --for=jsonpath='{status.healthStatus}'=green tenants.minio.min.io myminio --timeout=300s
echo ""
echo -e "${GREEN}✓ MinIO Tenant setup completed${NC}"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Creating MinIO Buckets ${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}Creating bucket list ConfigMap...${NC}"
kubectl -n "${MINIO_TENANT_NAMESPACE}" apply -f ${SCRIPT_DIR}/minio/buckets/bucket-list-configmap.yaml

# Delete existing job if it exists (jobs are immutable)
if kubectl -n "${MINIO_TENANT_NAMESPACE}" get job minio-create-bucket &>/dev/null; then
    echo -e "${YELLOW}Deleting existing bucket creation job...${NC}"
    kubectl -n "${MINIO_TENANT_NAMESPACE}" delete job minio-create-bucket
fi

echo -e "${YELLOW}Running bucket creation job...${NC}"
kubectl -n "${MINIO_TENANT_NAMESPACE}" apply -f ${SCRIPT_DIR}/minio/buckets/create-bucket.yaml

echo -e "${YELLOW}Waiting for bucket creation job to complete...${NC}"
kubectl -n "${MINIO_TENANT_NAMESPACE}" wait --for=condition=complete job minio-create-bucket --timeout=300s

echo ""
echo -e "${GREEN}✓ MinIO buckets created successfully${NC}"
echo ""

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

echo -e "${YELLOW}Retrieving MinIO credentials...${NC}"
MINIO_ACCESS_KEY=$(kubectl -n "${MINIO_TENANT_NAMESPACE}" get secret storage-user -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
MINIO_SECRET_KEY=$(kubectl -n "${MINIO_TENANT_NAMESPACE}" get secret storage-user -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)

BUCKET="product-csvs"
SUBFOLDER="schema/product-data"
OBJECT="productInventory.csv"
FILE="${SCRIPT_DIR}/data/productInventory.csv"

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
# The output format is typically:
# Access Key: <key>
# Secret Key: <secret>
export GRAVITINO_S3_ACCESS_KEY
GRAVITINO_S3_ACCESS_KEY=$(echo "$SVCACCT_OUTPUT" | grep "Access Key" | awk '{print $3}')
export GRAVITINO_S3_SECRET_KEY
GRAVITINO_S3_SECRET_KEY=$(echo "$SVCACCT_OUTPUT" | grep "Secret Key" | awk '{print $3}')

if [ -z "$GRAVITINO_S3_ACCESS_KEY" ] || [ -z "$GRAVITINO_S3_SECRET_KEY" ]; then
    echo -e "${RED}Failed to parse service account credentials${NC}"
    echo -e "${RED}Output: ${SVCACCT_OUTPUT}${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Service account created successfully${NC}"
echo ""

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up PostgreSQL ${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if Postgres deployment is ready
echo -e "${YELLOW}Checking that Postgres is ready...${NC}"
kubectl -n "${POSTGRES_NAMESPACE}" wait --for=condition=available deployment postgres --timeout=300s

echo -e "${GREEN}✓ Postgres is ready${NC}"
echo ""

# Setup port-forward for Postgres
# Check if port-forward is already running
if ! pgrep -f "port-forward.*postgres.*5432:5432" > /dev/null; then
    echo -e "${YELLOW}Starting port-forward to Postgres service...${NC}"
    kubectl -n "${POSTGRES_NAMESPACE}" port-forward svc/postgres 5432:5432 > /dev/null 2>&1 &
    POSTGRES_PORT_FORWARD_PID=$!
    # Wait for port-forward to be ready
    sleep 3
    echo -e "${GREEN}✓ Postgres port-forward started${NC}"
else
    echo -e "${GREEN}✓ Postgres port-forward already running${NC}"
    POSTGRES_PORT_FORWARD_PID=$(pgrep -f "port-forward.*postgres.*5432:5432")
fi
echo ""

echo -e "${YELLOW}Creating PostgreSQL tables and loading data...${NC}"
${SCRIPT_DIR}/example-resources/create-tables.sh
echo ""

echo -e "${YELLOW}Creating Gravitino catalog for PostgreSQL...${NC}"
${SCRIPT_DIR}/example-resources/create-relational-catalog.sh
echo ""

echo -e "${YELLOW}Creating Gravitino fileset catalog for MinIO...${NC}"
${SCRIPT_DIR}/example-resources/create-fileset-catalog.sh
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Gravitino Web UI: ${BLUE}http://localhost:8090${NC}"
echo -e "MinIO Console: ${BLUE}https://localhost:9001${NC}"
echo -e "PostgreSQL: ${BLUE}localhost:5432${NC} (Database: testdb, User: admin, Password: admin)"
echo ""
echo -e "Port-forward PIDs:"
echo -e "  Gravitino: ${PORT_FORWARD_PID}"
echo -e "  MinIO: ${MINIO_PORT_FORWARD_PID}"
echo -e "  PostgreSQL: ${POSTGRES_PORT_FORWARD_PID}"
echo ""
echo -e "To stop the port-forwards, run:"
echo -e "  ${YELLOW}kill ${PORT_FORWARD_PID} ${MINIO_PORT_FORWARD_PID} ${POSTGRES_PORT_FORWARD_PID}${NC}"
echo -e "To restart the Gravitino port-forward, run:"
echo -e "  ${YELLOW}kubectl -n ${GRAVITINO_NAMESPACE} port-forward svc/gravitino 8090:8090${NC}"
echo -e "To restart the MinIO port-forward, run:"
echo -e "  ${YELLOW}kubectl -n ${MINIO_TENANT_NAMESPACE} port-forward svc/myminio-hl 9000:9000${NC}"
echo -e "To restart the Postgres port-forward, run:"
echo -e "  ${YELLOW}kubectl -n ${POSTGRES_NAMESPACE} port-forward svc/postgres 5432:5432${NC}"
echo ""