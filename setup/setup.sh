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
"${SCRIPT_DIR}"/example-resources/setup-kafka.sh
echo ""

# MinIO tenant and buckets are created during installation (install.sh)

# Upload data to MinIO
"${SCRIPT_DIR}"/example-resources/upload-minio-data.sh

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

echo -e "${YELLOW}Creating Gravitino Iceberg REST catalog...${NC}"
${SCRIPT_DIR}/example-resources/create-iceberg-catalog.sh
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Gravitino Web UI: ${BLUE}http://localhost:8090${NC}"
echo -e "PostgreSQL: ${BLUE}localhost:5432${NC} (Database: testdb, User: admin, Password: admin)"
echo ""
echo -e "Port-forward PIDs:"
echo -e "  Gravitino: ${PORT_FORWARD_PID}"
echo -e "  PostgreSQL: ${POSTGRES_PORT_FORWARD_PID}"
echo ""
echo -e "To stop the port-forwards, run:"
echo -e "  ${YELLOW}kill ${PORT_FORWARD_PID} ${POSTGRES_PORT_FORWARD_PID}${NC}"
echo -e "To restart the Gravitino port-forward, run:"
echo -e "  ${YELLOW}kubectl -n ${GRAVITINO_NAMESPACE} port-forward svc/gravitino 8090:8090${NC}"
echo -e "To restart the Postgres port-forward, run:"
echo -e "  ${YELLOW}kubectl -n ${POSTGRES_NAMESPACE} port-forward svc/postgres 5432:5432${NC}"
echo ""