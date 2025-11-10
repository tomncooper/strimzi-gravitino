#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/../common.sh"

# Setup Kafka Topics
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up Kafka Topics ${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}Creating example Kafka topics...${NC}"
kubectl -n "${KAFKA_NAMESPACE}" apply -f ${SCRIPT_DIR}/example-topics.yaml

echo -e "${YELLOW}Waiting for Kafka topics to be ready...${NC}"
kubectl -n "${KAFKA_NAMESPACE}" wait --for=condition=Ready kafkatopic --all --timeout=300s

echo -e "${GREEN}✓ All Kafka topics are ready${NC}"
echo ""

# Setup Kafka Catalog in Gravitino
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setting up Kafka Catalog in Gravitino ${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if catalog exists
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    http://localhost:8090/api/metalakes/${METALAKE}/catalogs/my_cluster_catalog 2>/dev/null | grep -q "NoSuchCatalogException"; then
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
    }' http://localhost:8090/api/metalakes/${METALAKE}/catalogs
    echo ""
else
    echo -e "${GREEN}✓ Catalog already exists${NC}"
fi

echo -e "${YELLOW}Creating tags...${NC}"
${SCRIPT_DIR}/create-tags.sh
echo ""
echo -e "${YELLOW}Attaching tags to topics...${NC}"
${SCRIPT_DIR}/attach-tags.sh
echo ""
echo -e "${GREEN}✓ Kafka setup completed${NC}"
echo ""
