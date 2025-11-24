#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="product-recommendation"
APP_VERSION="1.0.0"
NAMESPACE="product-recommendation"
IMAGE_NAME="${APP_NAME}:${APP_VERSION}"

# Parse command line arguments
ACTION=${1:-"help"}

function show_help() {
    echo "Usage: $0 [ACTION]"
    echo ""
    echo "Actions:"
    echo "  build            - Build Maven project"
    echo "  push_to_minikube - Build Container image using podman and load into Minikube"
    echo "  deploy           - Deploy to Kubernetes"
    echo "  all              - Build, create container image, and deploy"
    echo "  logs             - View application logs"
    echo "  delete           - Delete Kubernetes deployment"
    echo "  help             - Show this help message"
    echo ""
}

function build_maven() {
    echo -e "${YELLOW}Building Maven project...${NC}"
    mvn clean package -DskipTests
    echo -e "${GREEN}✓ Maven build completed${NC}"
}

function build_docker() {
    echo -e "${YELLOW}Building Docker image: ${IMAGE_NAME}...${NC}"
    docker build -t ${IMAGE_NAME} .
    echo -e "${GREEN}✓ Docker image built: ${IMAGE_NAME}${NC}"
}

function podman_to_minikube() {
    echo -e "${YELLOW}Building Container image ${IMAGE_NAME} using podman...${NC}"
    podman build --tag ${IMAGE_NAME} .
    echo -e "${GREEN}✓ Container image built: ${IMAGE_NAME}${NC}"
    
    # Create temporary directory for image tar file
    TEMP_DIR=$(mktemp -d)
    IMAGE_TAR="${TEMP_DIR}/${APP_NAME}-${APP_VERSION}.tar"
    
    echo -e "${YELLOW}Saving Container image to tar file...${NC}"
    podman save -o "${IMAGE_TAR}" ${IMAGE_NAME}
    echo -e "${GREEN}✓ Container image saved to: ${IMAGE_TAR}${NC}"
    
    echo -e "${YELLOW}Loading Container image into Minikube...${NC}"
    minikube image load "${IMAGE_TAR}"
    echo -e "${GREEN}✓ Container image loaded into Minikube${NC}"
    
    # Clean up temporary directory
    rm -rf "${TEMP_DIR}"
    echo -e "${GREEN}✓ Temporary files cleaned up${NC}"
}

function deploy_k8s() {
    echo -e "${YELLOW}Deploying to Kubernetes...${NC}"

    # Create namespace
    echo "Creating namespace..."
    kubectl apply -f kubernetes/namespace.yaml

    # Copy MinIO credentials from metadata namespace
    echo "Copying MinIO credentials..."
    kubectl get secret gravitino-minio-credentials -n metadata -o json 2>/dev/null | \
      jq 'del(.metadata.namespace, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp)' | \
      jq '.metadata.name = "minio-credentials"' | \
      jq '.metadata.namespace = "product-recommendation"' | \
      kubectl apply -f - || echo "Note: Secret may already exist"

    # Deploy application
    echo "Deploying application..."
    kubectl apply -f kubernetes/deployment.yaml

    echo -e "${GREEN}✓ Deployment completed${NC}"
    echo ""
    echo "Check deployment status:"
    echo "  kubectl -n ${NAMESPACE} get pods"
    echo "  kubectl -n ${NAMESPACE} logs -l app=${APP_NAME} -f"
}

function view_logs() {
    echo -e "${YELLOW}Viewing application logs...${NC}"
    kubectl -n ${NAMESPACE} logs -l app=${APP_NAME} -f
}

function delete_deployment() {
    echo -e "${YELLOW}Deleting Kubernetes deployment...${NC}"
    kubectl delete -f kubernetes/deployment.yaml || echo "Deployment not found"
    kubectl delete namespace ${NAMESPACE} || echo "Namespace not found"
    echo -e "${GREEN}✓ Deployment deleted${NC}"
}

# Execute action
case ${ACTION} in
    build)
        build_maven
        ;;
    push_to_minikube)
        podman_to_minikube
        ;;
    deploy)
        deploy_k8s
        ;;
    all)
        build_maven
        podman_to_minikube
        deploy_k8s
        ;;
    logs)
        view_logs
        ;;
    delete)
        delete_deployment
        ;;
    help)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown action: ${ACTION}${NC}"
        show_help
        exit 1
        ;;
esac
