#!/bin/bash
# filepath: install.sh

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/common.sh"

# Configuration
GRAVITINO_VERSION="${1:-v1.0.0}"
MINIO_VERSION="${2:-v7.1.1}"

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}Gravitino, Strimzi, Kafka and MinIO Installation ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is not installed${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is not installed${NC}" >&2; exit 1; }
echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Check for active Kubernetes cluster
echo -e "${YELLOW}Checking for active Kubernetes cluster...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Error: No active Kubernetes cluster found. Please ensure kubectl is connected to a cluster.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✓ Active Kubernetes cluster detected${NC}"
echo ""

# Install Gravitino
echo -e "${BLUE}=== Installing Gravitino ===${NC}"

# Check if Gravitino is already installed
if kubectl get namespace "${GRAVITINO_NAMESPACE}" >/dev/null 2>&1 && \
   kubectl -n "${GRAVITINO_NAMESPACE}" get deployment gravitino >/dev/null 2>&1; then
    echo -e "${YELLOW}Gravitino is already installed, skipping installation...${NC}"
else
    echo -e "${YELLOW}Generating Gravitino manifests for version ${GRAVITINO_VERSION}...${NC}"
    ${SCRIPT_DIR}/gravitino-manifests.sh "${GRAVITINO_VERSION}" "${GRAVITINO_NAMESPACE}"

    echo -e "${YELLOW}Creating ${GRAVITINO_NAMESPACE} namespace...${NC}"
    kubectl create namespace "${GRAVITINO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${YELLOW}Applying Gravitino manifests...${NC}"
    MANIFEST_FILE=$(ls ${SCRIPT_DIR}/manifests/gravitino/gravitino-manifests-*.yaml | head -n 1)
    kubectl apply -f "${MANIFEST_FILE}"
fi

echo -e "${YELLOW}Waiting for Gravitino to be ready...${NC}"
kubectl -n "${GRAVITINO_NAMESPACE}" wait --for=condition=available deployment gravitino --timeout=300s

echo -e "${GREEN}✓ Gravitino installed successfully${NC}"
echo ""

# Install Strimzi Kafka
echo -e "${BLUE}=== Installing Strimzi Kafka ===${NC}"

# Check if Strimzi operator is already installed
if helm list -n "${KAFKA_NAMESPACE}" | grep -q strimzi-cluster-operator; then
    echo -e "${YELLOW}Strimzi operator is already installed, skipping installation...${NC}"
else
    echo -e "${YELLOW}Installing Strimzi Kafka operator...${NC}"
    helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
      -n "${KAFKA_NAMESPACE}" --create-namespace --wait
fi

# Check if Kafka cluster already exists
if kubectl -n "${KAFKA_NAMESPACE}" get kafka "${KAFKA_CLUSTER_NAME}" >/dev/null 2>&1; then
    echo -e "${YELLOW}Kafka cluster '${KAFKA_CLUSTER_NAME}' already exists, skipping creation...${NC}"
else
    echo -e "${YELLOW}Creating Kafka cluster...${NC}"
    kubectl apply -f https://strimzi.io/examples/latest/kafka/kafka-single-node.yaml -n "${KAFKA_NAMESPACE}"
fi

echo -e "${YELLOW}Waiting for Kafka cluster to be ready...${NC}"
kubectl -n "${KAFKA_NAMESPACE}" wait kafka/"${KAFKA_CLUSTER_NAME}" --for=condition=Ready --timeout=300s

echo -e "${GREEN}✓ Strimzi Kafka installed successfully${NC}"
echo ""

# Install MinIO Operator
echo -e "${BLUE}=== Installing MinIO Operator ===${NC}"
kubectl kustomize ${SCRIPT_DIR}/minio/operator | kubectl apply -f -

echo -e "${YELLOW}Waiting for MinIO Operator to be ready...${NC}"
kubectl -n "${MINIO_OPERATOR_NAMESPACE}" wait --for=condition=available deployment minio-operator --timeout=300s