#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/common.sh"

# Configuration
GRAVITINO_VERSION="${1:-v1.0.0}"
CERT_MANAGER_VERSION="1.19.1"
FLINK_OPERATOR_VERSION="1.13.0"

# Create temporary directory for status tracking
STATUS_DIR=$(mktemp -d)

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}Gravitino Demo Environment Installation Script ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
check_prerequisite kubectl
check_prerequisite helm
check_prerequisite psql
check_prerequisite jq
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

# Function to install Gravitino
install_gravitino() {
    local status_file="${STATUS_DIR}/gravitino"
    local log_file="${STATUS_DIR}/gravitino.log"
    {
        echo "[Gravitino] Starting installation..."

        # Check if Gravitino is already installed
        if kubectl get namespace "${GRAVITINO_NAMESPACE}" >/dev/null 2>&1 && \
           kubectl -n "${GRAVITINO_NAMESPACE}" get deployment gravitino >/dev/null 2>&1; then
            echo "[Gravitino] Already installed, skipping installation..."
        else
            echo "[Gravitino] Generating manifests for version ${GRAVITINO_VERSION}..."
            "${SCRIPT_DIR}"/gravitino-manifests.sh "${GRAVITINO_VERSION}" "${GRAVITINO_NAMESPACE}" || {
                echo "FAILED" > "$status_file"
                echo "[Gravitino] Failed to generate manifests"
                return 1
            }

            echo "[Gravitino] Creating ${GRAVITINO_NAMESPACE} namespace..."
            kubectl create namespace "${GRAVITINO_NAMESPACE}" || {
                echo "FAILED" > "$status_file"
                echo "[Gravitino] Failed to create namespace"
                return 1
            }

            echo "[Gravitino] Creating MinIO credentials secret..."
            "${SCRIPT_DIR}"/gravitino-install/create-minio-credentials-secret.sh || {
                echo "FAILED" > "$status_file"
                echo "[Gravitino] Failed to create MinIO credentials secret"
                return 1
            }

            echo "[Gravitino] Applying manifests..."
            kubectl apply -k "${SCRIPT_DIR}"/gravitino-install || {
                echo "FAILED" > "$status_file"
                echo "[Gravitino] Failed to apply manifests"
                return 1
            }
        fi

        echo "[Gravitino] Waiting for all deployments to be ready (this can take 5+ minutes)..."
        kubectl -n "${GRAVITINO_NAMESPACE}" wait --for=condition=available deployment --all --timeout=420s || {
            echo "FAILED" > "$status_file"
            echo "[Gravitino] Deployments failed to become ready"
            return 1
        }

        echo "SUCCESS" > "$status_file"
        echo "[Gravitino] ✓ Installed successfully"
        return 0
    } &> "$log_file"
}

# Function to install Strimzi Kafka
install_kafka() {
    local status_file="${STATUS_DIR}/kafka"
    local log_file="${STATUS_DIR}/kafka.log"
    {
        echo "[Kafka] Starting installation..."

        # Check if Strimzi operator is already installed
        if helm list -n "${KAFKA_NAMESPACE}" 2>/dev/null | grep -q strimzi-cluster-operator; then
            echo "[Kafka] Strimzi operator already installed, skipping installation..."
        else
            echo "[Kafka] Installing Strimzi Kafka operator..."
            helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
              -n "${KAFKA_NAMESPACE}" --create-namespace --wait || {
                echo "FAILED" > "$status_file"
                echo "[Kafka] Failed to install Strimzi operator"
                return 1
            }
        fi

        # Check if Kafka cluster already exists
        if kubectl -n "${KAFKA_NAMESPACE}" get kafka "${KAFKA_CLUSTER_NAME}" >/dev/null 2>&1; then
            echo "[Kafka] Cluster '${KAFKA_CLUSTER_NAME}' already exists, skipping creation..."
        else
            echo "[Kafka] Creating Kafka cluster..."
            kubectl apply -k "${SCRIPT_DIR}"/kafka || {
                echo "FAILED" > "$status_file"
                echo "[Kafka] Failed to create Kafka cluster"
                return 1
            }
        fi

        echo "[Kafka] Waiting for Kafka cluster to be ready..."
        kubectl -n "${KAFKA_NAMESPACE}" wait kafka/"${KAFKA_CLUSTER_NAME}" --for=condition=Ready --timeout=300s || {
            echo "FAILED" > "$status_file"
            echo "[Kafka] Kafka cluster failed to become ready"
            return 1
        }

        echo "SUCCESS" > "$status_file"
        echo "[Kafka] ✓ Installed successfully"
        return 0
    } &> "$log_file"
}

# Function to install MinIO Operator
install_minio() {
    local status_file="${STATUS_DIR}/minio"
    local log_file="${STATUS_DIR}/minio.log"
    {
        echo "[MinIO] Starting installation..."

        echo "[MinIO] Applying MinIO Operator manifests..."
        kubectl apply -k "${SCRIPT_DIR}"/minio/operator || {
            echo "FAILED" > "$status_file"
            echo "[MinIO] Failed to apply manifests"
            return 1
        }

        echo "[MinIO] Waiting for MinIO Operator to be ready..."
        kubectl -n "${MINIO_OPERATOR_NAMESPACE}" wait --for=condition=available deployment minio-operator --timeout=300s || {
            echo "FAILED" > "$status_file"
            echo "[MinIO] Operator failed to become ready"
            return 1
        }

        # Check if MinIO tenant already exists
        if kubectl -n "${MINIO_TENANT_NAMESPACE}" get tenants.minio.min.io myminio >/dev/null 2>&1; then
            echo "[MinIO] Tenant 'myminio' already exists, skipping creation..."
        else
            echo "[MinIO] Creating MinIO tenant..."
            kubectl apply -k "${SCRIPT_DIR}"/minio/tenant || {
                echo "FAILED" > "$status_file"
                echo "[MinIO] Failed to create tenant"
                return 1
            }
        fi

        echo "[MinIO] Waiting for MinIO tenant to be healthy (this can take 3-5 minutes)..."
        kubectl wait --for=jsonpath='{.status.healthStatus}'=green \
            tenants.minio.min.io myminio -n "${MINIO_TENANT_NAMESPACE}" --timeout=300s || {
            echo "FAILED" > "$status_file"
            echo "[MinIO] Tenant failed to become healthy"
            return 1
        }

        echo "[MinIO] Tenant is healthy"

        echo "[MinIO] Creating bucket list ConfigMap..."
        kubectl -n "${MINIO_TENANT_NAMESPACE}" apply -f "${SCRIPT_DIR}"/minio/buckets/bucket-list-configmap.yaml || {
            echo "FAILED" > "$status_file"
            echo "[MinIO] Failed to create bucket list ConfigMap"
            return 1
        }

        # Delete existing job if it exists (jobs are immutable)
        if kubectl -n "${MINIO_TENANT_NAMESPACE}" get job minio-create-bucket &>/dev/null; then
            echo "[MinIO] Deleting existing bucket creation job..."
            kubectl -n "${MINIO_TENANT_NAMESPACE}" delete job minio-create-bucket
        fi

        echo "[MinIO] Running bucket creation job..."
        kubectl -n "${MINIO_TENANT_NAMESPACE}" apply -f "${SCRIPT_DIR}"/minio/buckets/create-bucket.yaml || {
            echo "FAILED" > "$status_file"
            echo "[MinIO] Failed to create bucket job"
            return 1
        }

        echo "[MinIO] Waiting for bucket creation job to complete..."
        kubectl -n "${MINIO_TENANT_NAMESPACE}" wait --for=condition=complete job minio-create-bucket --timeout=300s || {
            echo "FAILED" > "$status_file"
            echo "[MinIO] Bucket creation job failed to complete"
            return 1
        }

        echo "[MinIO] Buckets created successfully (test-bucket, product-csvs, iceberg-warehouse)"

        echo "SUCCESS" > "$status_file"
        echo "[MinIO] ✓ Installed successfully"
        return 0
    } &> "$log_file"
}

# Function to install PostgreSQL
install_postgres() {
    local status_file="${STATUS_DIR}/postgres"
    local log_file="${STATUS_DIR}/postgres.log"
    {
        echo "[PostgreSQL] Starting installation..."

        # Check if namespace exists
        if ! kubectl get namespace "${POSTGRES_NAMESPACE}" >/dev/null 2>&1; then
            echo "[PostgreSQL] Creating ${POSTGRES_NAMESPACE} namespace..."
            kubectl create namespace "${POSTGRES_NAMESPACE}" || {
                echo "FAILED" > "$status_file"
                echo "[PostgreSQL] Failed to create namespace"
                return 1
            }
        fi

        echo "[PostgreSQL] Applying PostgreSQL manifests..."
        kubectl apply -f "${SCRIPT_DIR}"/postgres/postgres-resources.yaml -n "${POSTGRES_NAMESPACE}" || {
            echo "FAILED" > "$status_file"
            echo "[PostgreSQL] Failed to apply manifests"
            return 1
        }

        echo "[PostgreSQL] Waiting for PostgreSQL to be ready..."
        kubectl -n "${POSTGRES_NAMESPACE}" wait --for=condition=available deployment postgres --timeout=300s || {
            echo "FAILED" > "$status_file"
            echo "[PostgreSQL] Deployment failed to become ready"
            return 1
        }

        echo "SUCCESS" > "$status_file"
        echo "[PostgreSQL] ✓ Installed successfully"
        return 0
    } &> "$log_file"
}

# Function to install Apicurio Registry
install_apicurio() {
    local status_file="${STATUS_DIR}/apicurio"
    local log_file="${STATUS_DIR}/apicurio.log"
    {
        echo "[Apicurio] Starting installation..."

        # Check if Apicurio deployment already exists
        if kubectl get namespace "${APICURIO_NAMESPACE}" >/dev/null 2>&1 && \
           kubectl -n "${APICURIO_NAMESPACE}" get deployment apicurio-registry >/dev/null 2>&1; then
            echo "[Apicurio] Already installed, skipping installation..."
        else
            echo "[Apicurio] Applying Apicurio Registry manifests..."
            kubectl apply -k "${SCRIPT_DIR}"/apicurio-registry || {
                echo "FAILED" > "$status_file"
                echo "[Apicurio] Failed to apply manifests"
                return 1
            }
        fi

        echo "[Apicurio] Waiting for Apicurio Registry to be ready..."
        kubectl -n "${APICURIO_NAMESPACE}" wait --for=condition=available deployment apicurio-registry --timeout=300s || {
            echo "FAILED" > "$status_file"
            echo "[Apicurio] Deployment failed to become ready"
            return 1
        }

        echo "SUCCESS" > "$status_file"
        echo "[Apicurio] ✓ Installed successfully"
        return 0
    } &> "$log_file"
}

# Function to install Apache Flink Kubernetes Operator
install_flink() {
    local status_file="${STATUS_DIR}/flink"
    local log_file="${STATUS_DIR}/flink.log"
    {

        echo "Installing CertManager version ${CERT_MANAGER_VERSION} which is needed by the Flink Kubernetes Operator"

        # Install CertManager - this is needed by the Flink Kubernetes Operator
        echo "[CertManager] Checking for CertManager install"
        if kubectl get namespace cert-manager ; then
            echo "[CertManager] CertManager is already installed"
        else
            kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml
        fi

        echo "[Flink] Starting installation of Flink Kubernetes Operator version ${FLINK_OPERATOR_VERSION}..."

        # Check if Helm repository already exists
        if ! helm repo list 2>/dev/null | grep -q flink-operator-repo; then
            echo "[Flink] Adding Flink Operator Helm repository..."
            helm repo add --force-update flink-operator-repo https://downloads.apache.org/flink/flink-kubernetes-operator-${FLINK_OPERATOR_VERSION}/ || {
                echo "FAILED" > "$status_file"
                echo "[Flink] Failed to add Helm repository"
                return 1
            }
        else
            echo "[Flink] Flink Operator Helm repository already exists, skipping add..."
        fi

        echo "[Flink] Updating Helm repositories..."
        helm repo update || {
            echo "FAILED" > "$status_file"
            echo "[Flink] Failed to update Helm repositories"
            return 1
        }

        echo "[Flink] Waiting for cert-manager webhook to be ready..."
        kubectl -n cert-manager wait --for=condition=Available --timeout=300s deployment cert-manager-webhook

        echo "[Flink] Checking for Flink Operator install"
        if kubectl -n "${FLINK_NAMESPACE}" get deployment flink-kubernetes-operator ; then
            echo "[Flink] Flink Operator already installed"
        else
            echo "Installing the Flink Operator"
            helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator \
            --set podSecurityContext=null \
            --set defaultConfiguration."log4j-operator\.properties"=monitorInterval\=30 \
            --set defaultConfiguration."log4j-console\.properties"=monitorInterval\=30 \
            --set defaultConfiguration."flink-conf\.yaml"="kubernetes.operator.metrics.reporter.prom.factory.class\:\ org.apache.flink.metrics.prometheus.PrometheusReporterFactory
            kubernetes.operator.metrics.reporter.prom.port\:\ 9249 " \
            --create-namespace \
            -n "${FLINK_NAMESPACE}"
        fi

        echo "[Flink] Waiting for Flink Operator to be ready..."
        kubectl -n "${FLINK_NAMESPACE}" wait --for=condition=available deployment --all --timeout=300s || {
            echo "FAILED" > "$status_file"
            echo "[Flink] Operator failed to become ready"
            return 1
        }

        echo "SUCCESS" > "$status_file"
        echo "[Flink] ✓ Installed successfully"
        return 0
    } &> "$log_file"
}

echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}Installing components in parallel...${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

echo -e "${YELLOW}Installation logs:${NC}"
echo -e "  Kafka:      ${STATUS_DIR}/kafka.log"
echo -e "  MinIO:      ${STATUS_DIR}/minio.log"
echo -e "  PostgreSQL: ${STATUS_DIR}/postgres.log"
echo -e "  Apicurio:   ${STATUS_DIR}/apicurio.log"
echo -e "  Flink:      ${STATUS_DIR}/flink.log"
echo ""
echo -e "${YELLOW}Tip: Monitor logs with: tail -f ${STATUS_DIR}/*.log${NC}"
echo ""

install_kafka &
PID_KAFKA=$!

install_minio &
PID_MINIO=$!

install_postgres &
PID_POSTGRES=$!

install_apicurio &
PID_APICURIO=$!

install_flink &
PID_FLINK=$!

echo -e "${YELLOW}Waiting for Kafka, MinIO, PostgreSQL, Apicurio, and Flink to complete installation...${NC}"
echo ""

wait $PID_KAFKA $PID_MINIO $PID_POSTGRES $PID_APICURIO $PID_FLINK

echo -e "${YELLOW}Installing Gravitino...${NC}"
echo ""
echo -e "${YELLOW}Installation logs:${NC}"
echo -e "  Gravitino:  ${STATUS_DIR}/gravitino.log"

install_gravitino

echo ""
echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}Installation Summary${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# Check results
FAILED_COMPONENTS=()

if [ -f "${STATUS_DIR}/gravitino" ] && [ "$(cat "${STATUS_DIR}"/gravitino)" == "SUCCESS" ]; then
    echo -e "${GREEN}✓ Gravitino: SUCCESS${NC}"
else
    echo -e "${RED}✗ Gravitino: FAILED${NC}"
    FAILED_COMPONENTS+=("Gravitino")
fi

if [ -f "${STATUS_DIR}/kafka" ] && [ "$(cat "${STATUS_DIR}"/kafka)" == "SUCCESS" ]; then
    echo -e "${GREEN}✓ Kafka: SUCCESS${NC}"
else
    echo -e "${RED}✗ Kafka: FAILED${NC}"
    FAILED_COMPONENTS+=("Kafka")
fi

if [ -f "${STATUS_DIR}/minio" ] && [ "$(cat "${STATUS_DIR}"/minio)" == "SUCCESS" ]; then
    echo -e "${GREEN}✓ MinIO: SUCCESS${NC}"
else
    echo -e "${RED}✗ MinIO: FAILED${NC}"
    FAILED_COMPONENTS+=("MinIO")
fi

if [ -f "${STATUS_DIR}/postgres" ] && [ "$(cat "${STATUS_DIR}"/postgres)" == "SUCCESS" ]; then
    echo -e "${GREEN}✓ PostgreSQL: SUCCESS${NC}"
else
    echo -e "${RED}✗ PostgreSQL: FAILED${NC}"
    FAILED_COMPONENTS+=("PostgreSQL")
fi

if [ -f "${STATUS_DIR}/apicurio" ] && [ "$(cat "${STATUS_DIR}"/apicurio)" == "SUCCESS" ]; then
    echo -e "${GREEN}✓ Apicurio: SUCCESS${NC}"
else
    echo -e "${RED}✗ Apicurio: FAILED${NC}"
    FAILED_COMPONENTS+=("Apicurio")
fi

if [ -f "${STATUS_DIR}/flink" ] && [ "$(cat "${STATUS_DIR}"/flink)" == "SUCCESS" ]; then
    echo -e "${GREEN}✓ Flink: SUCCESS${NC}"
else
    echo -e "${RED}✗ Flink: FAILED${NC}"
    FAILED_COMPONENTS+=("Flink")
fi

echo ""

# Report final status
if [ ${#FAILED_COMPONENTS[@]} -eq 0 ]; then
    echo -e "${GREEN}===========================================================${NC}"
    echo -e "${GREEN}All components installed successfully!${NC}"
    echo -e "${GREEN}===========================================================${NC}"
    echo ""

    # Clean up temporary directory on success
    rm -rf "${STATUS_DIR}"

    exit 0
else
    echo -e "${RED}===========================================================${NC}"
    echo -e "${RED}Installation failed for: ${FAILED_COMPONENTS[*]}${NC}"
    echo -e "${RED}===========================================================${NC}"
    echo ""
    echo -e "${YELLOW}Logs preserved at: ${STATUS_DIR}${NC}"
    echo ""
    echo -e "${YELLOW}Review logs for troubleshooting:${NC}"
    for component in "${FAILED_COMPONENTS[@]}"; do
        component_lower=$(echo "$component" | tr "[:upper:]" "[:lower:]")
        echo -e "  cat ${STATUS_DIR}/${component_lower}.log"
    done
    echo ""

    exit 1
fi
