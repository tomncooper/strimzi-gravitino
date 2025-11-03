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

echo -e "${YELLOW}Starting port-forward to Gravitino service...${NC}"
kubectl -n "${GRAVITINO_NAMESPACE}" port-forward svc/gravitino 8090:8090 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port-forward to be ready
sleep 5

echo -e "${YELLOW}Creating metalake...${NC}"
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" -d '{
    "name":"strimzi_kafka",
    "comment":"This metalake holds all Strimzi related metadata",
    "properties":{}
}' http://localhost:8090/api/metalakes

echo ""

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

echo -e "${YELLOW}Creating tags...${NC}"
${SCRIPT_DIR}/example-resources/create-tags.sh
echo ""
echo -e "${YELLOW}Attaching tags to topics...${NC}"
${SCRIPT_DIR}/example-resources/attach-tags.sh
echo ""
echo -e "${GREEN}✓ Gravitino setup completed${NC}"
echo ""

# Verify installation
echo -e "${BLUE}=== Verifying Installation ===${NC}"

echo -e "${YELLOW}Checking Kafka topics in Gravitino catalog...${NC}"
TOPICS=$(curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" \
  http://localhost:8090/api/metalakes/strimzi_kafka/catalogs/my_cluster_catalog/schemas/default/topics)

echo "$TOPICS" | jq '.' || echo "$TOPICS"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Gravitino Web UI: ${BLUE}http://localhost:8090${NC}"
echo -e "Port-forward PID: ${PORT_FORWARD_PID}"
echo ""
echo -e "To stop the port-forward, run: ${YELLOW}kill ${PORT_FORWARD_PID}${NC}"
echo -e "To restart the port-forward, run: ${YELLOW}kubectl -n ${GRAVITINO_NAMESPACE} port-forward svc/gravitino 8090:8090${NC}"
echo ""