#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GRAVITINO_NAMESPACE="metadata"
KAFKA_NAMESPACE="kafka"
KAFKA_CLUSTER_NAME="my-cluster"
MINIO_OPERATOR_NAMESPACE="minio-operator"
MINIO_TENANT_NAMESPACE="minio-tenant"
POSTGRES_NAMESPACE="postgres"
METALAKE="demolake"

# Function to check if a command is installed
check_prerequisite() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}Error: $cmd is not installed${NC}" >&2
        exit 1
    fi
}
