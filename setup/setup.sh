#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/common.sh"

# Setup Gravitino
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up Kafka Topics ${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}Creating example Kafka topics...${NC}"
kubectl -n "${KAFKA_NAMESPACE}" apply -f ${SCRIPT_DIR}/example-resources/example-topics.yaml

echo -e "${YELLOW}Waiting for Kafka topics to be ready...${NC}"
kubectl -n "${KAFKA_NAMESPACE}" wait --for=condition=Ready kafkatopic --all --timeout=300s

echo -e "${GREEN}✓ All Kafka topics are ready${NC}"
echo ""

# Setup Gravitino
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up Kafka metadata in Gravitino ${NC}"
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
    http://localhost:8090/api/metalakes/strimzi_kafka 2>/dev/null | grep -q "NoSuchMetalakeException"; then
    echo -e "${YELLOW}Creating metalake...${NC}"
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
      -H "Content-Type: application/json" -d '{
        "name":"strimzi_kafka",
        "comment":"This metalake holds all Strimzi related metadata",
        "properties":{}
    }' http://localhost:8090/api/metalakes
    echo ""
else
    echo -e "${GREEN}✓ Metalake already exists${NC}"
fi

# Check if catalog exists
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    http://localhost:8090/api/metalakes/strimzi_kafka/catalogs/my_cluster_catalog 2>/dev/null | grep -q "NoSuchCatalogException"; then
    echo -e "${YELLOW}Adding Kafka cluster as catalog...${NC}"
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
      -H "Content-Type: application/json" -d '{
        "name": "my_cluster_catalog",
        "type": "MESSAGING",
        "comment": "Catalog for the my_cluster Kafka cluster",
        "provider": "kafka",
        "properties": {
            "bootstrap.servers": "my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092"
        }
    }' http://localhost:8090/api/metalakes/strimzi_kafka/catalogs
    echo ""
else
    echo -e "${GREEN}✓ Catalog already exists${NC}"
fi

echo -e "${YELLOW}Creating tags...${NC}"
${SCRIPT_DIR}/example-resources/create-tags.sh
echo ""
echo -e "${YELLOW}Attaching tags to topics...${NC}"
${SCRIPT_DIR}/example-resources/attach-tags.sh
echo ""
echo -e "${GREEN}✓ Gravitino setup completed${NC}"
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

echo -e "${YELLOW}Checking if productInventory.csv already exists...${NC}"
if mc stat myminio/${BUCKET}/${OBJECT} --insecure &>/dev/null; then
    echo -e "${GREEN}✓ productInventory.csv already exists in bucket${NC}"
else
    echo -e "${YELLOW}Uploading productInventory.csv to ${BUCKET}...${NC}"
    mc cp "${FILE}" myminio/${BUCKET}/${OBJECT} --insecure
    echo -e "${GREEN}✓ Data uploaded successfully${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Gravitino Web UI: ${BLUE}http://localhost:8090${NC}"
echo -e "MinIO Console: ${BLUE}https://localhost:9001${NC}"
echo ""
echo -e "Port-forward PIDs:"
echo -e "  Gravitino: ${PORT_FORWARD_PID}"
echo -e "  MinIO: ${MINIO_PORT_FORWARD_PID}"
echo ""
echo -e "To stop the port-forwards, run:"
echo -e "  ${YELLOW}kill ${PORT_FORWARD_PID} ${MINIO_PORT_FORWARD_PID}${NC}"
echo -e "To restart the Gravitino port-forward, run:"
echo -e "  ${YELLOW}kubectl -n ${GRAVITINO_NAMESPACE} port-forward svc/gravitino 8090:8090${NC}"
echo -e "To restart the MinIO port-forward, run:"
echo -e "  ${YELLOW}kubectl -n ${MINIO_TENANT_NAMESPACE} port-forward svc/myminio-hl 9000:9000${NC}"
echo ""