# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository demonstrates deploying Apache Gravitino (a unified metadata management platform) integrated with a Strimzi-managed Kafka cluster on Kubernetes. The setup includes MinIO for S3-compatible storage, PostgreSQL for relational data, and shows metadata management operations across these systems.

## Architecture

### Component Layout

- **Gravitino**: Deployed in `metadata` namespace, provides unified metadata API
- **Strimzi Kafka**: Deployed in `kafka` namespace, Kafka cluster named `my-cluster`
- **MinIO**: Operator in `minio-operator` namespace, tenant in `minio-tenant` namespace
- **PostgreSQL**: Deployed in `postgres` namespace for relational data
- **Apicurio Registry**: Deployed in `registry` namespace, provides schema registry for Kafka
- **Data Generator**: Deployed in `data-generator` namespace, generates sample data for Kafka topics

### Gravitino Hierarchy

Gravitino organizes metadata in a hierarchy:
- **Metalake** (`demolake`): Top-level container for all metadata
- **Catalogs**: Collections for specific data systems
  - `my_cluster_catalog`: MESSAGING catalog for Kafka topics
  - `product_files`: FILESET catalog for S3/MinIO data
  - `postgres_catalog`: RELATIONAL catalog for PostgreSQL
  - `iceberg_rest_catalog`: RELATIONAL catalog for Apache Iceberg tables
- **Schemas**: Logical groupings within catalogs
- **Objects**: Actual data objects (topics, filesets, tables)
- **Tags**: Hierarchical metadata labels (dev, staging, prod, pii) applied to objects

### Installation Flow

The `gravitino-manifests.sh` script extracts Helm manifests from the Gravitino git submodule at `setup/gravitino/`. It checks out a specific version tag, packages the Helm chart, and generates Kubernetes manifests with kustomize. This approach avoids runtime Helm dependencies.

The `install.sh` script installs components with dependency management:
- **Phase 1 (Parallel)**: Kafka, MinIO, PostgreSQL, and Apicurio Registry install simultaneously for faster deployment
- **Phase 2 (Sequential)**: Gravitino installs after MinIO completes, ensuring MinIO credentials are available
- A shell script (`create-minio-credentials-secret.sh`) creates MinIO service account credentials and stores them in a Kubernetes secret before Gravitino deployment
- Individual log files track installation progress in a temporary directory
- Final summary shows success/failure status for each component
- Failed installations preserve logs for troubleshooting

## Common Commands

### Initial Setup

```bash
# Full automated installation (requires 6 CPUs, 16GB RAM minimum)
# Installs Gravitino, Kafka, MinIO, PostgreSQL, and Apicurio Registry in parallel
./setup/install.sh

# Setup metadata, catalogs, topics, tags, and data
# This script:
# 1. Creates the 'demolake' metalake
# 2. Sets up Kafka topics and catalog
# 3. Creates and attaches tags (dev, staging, prod, pii)
# 4. Deploys data generator application (depends on Kafka and Apicurio Registry)
# 5. Uploads data to MinIO
# 6. Sets up PostgreSQL tables and catalog
# 7. Creates fileset catalog for S3/MinIO access
# 8. Creates Iceberg REST catalog
# 9. Starts port-forwards for all services (PIDs displayed at end)
./setup/setup.sh
```

### Development Workflow

```bash
# Port-forward to Gravitino (required for API access)
kubectl -n metadata port-forward svc/gravitino 8090:8090

# Port-forward to MinIO (for S3 operations)
kubectl -n minio-tenant port-forward svc/myminio-hl 9000:9000

# Create Kafka topics
kubectl -n kafka apply -f setup/example-resources/example-topics.yaml

# Wait for topics to be ready
kubectl -n kafka wait --for=condition=Ready kafkatopic --all --timeout=300s
```

### Gravitino API Operations

All Gravitino operations use the REST API at `http://localhost:8090/api` (requires port-forward):

```bash
# Create metalake
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" -d '{
    "name":"demolake",
    "comment":"This metalake holds all the demo system metadata",
    "properties":{}
}' http://localhost:8090/api/metalakes

# Create Kafka catalog (MESSAGING type)
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" -d '{
    "name": "my_cluster_catalog",
    "type": "MESSAGING",
    "provider": "kafka",
    "properties": {
        "bootstrap.servers": "my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092"
    }
}' http://localhost:8090/api/metalakes/demolake/catalogs

# Create PostgreSQL catalog (RELATIONAL type)
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" -d '{
    "name": "postgres_catalog",
    "type": "RELATIONAL",
    "provider": "jdbc-postgresql",
    "properties": {
        "jdbc-url": "jdbc:postgresql://postgres.postgres.svc.cluster.local:5432/testdb",
        "jdbc-driver": "org.postgresql.Driver",
        "jdbc-database": "testdb",
        "jdbc-user": "admin",
        "jdbc-password": "admin"
    }
}' http://localhost:8090/api/metalakes/demolake/catalogs

# List catalogs
curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  http://localhost:8090/api/metalakes/demolake/catalogs
```

### MinIO Operations

```bash
# Get MinIO credentials
MINIO_ACCESS_KEY=$(kubectl -n minio-tenant get secret storage-user -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
MINIO_SECRET_KEY=$(kubectl -n minio-tenant get secret storage-user -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)

# Configure MinIO client (mc must be installed)
mc alias set myminio https://localhost:9000 "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}" --insecure

# Upload files
mc cp ./setup/data/productInventory.csv myminio/product-csvs/productInventory.csv --insecure
```

### PostgreSQL Operations

```bash
# Port-forward to PostgreSQL (required for direct access)
kubectl -n postgres port-forward svc/postgres 5432:5432

# Connect to PostgreSQL with psql
psql -h localhost -p 5432 -U admin -d testdb
# Password: admin

# Query the product inventory table
psql -h localhost -p 5432 -U admin -d testdb -c "SELECT * FROM product_inventory LIMIT 10;"

# The setup scripts create tables and load data from setup/data/productInventory.csv
# Table structure: id (integer), category (varchar), price (integer), quantity (integer)
```

### Apicurio Registry Operations

```bash
# Port-forward to Apicurio Registry (required for direct API access)
kubectl -n registry port-forward svc/apicurio-registry-service 8080:8080

# List all artifacts (schemas) in the registry
curl http://localhost:8080/apis/registry/v2/search/artifacts

# Get a specific artifact
curl http://localhost:8080/apis/registry/v2/groups/default/artifacts/{artifactId}

# Check Apicurio Registry deployment status
kubectl -n registry get deployment apicurio-registry
kubectl -n registry logs -l app=apicurio-registry

# Check data generator deployment status
kubectl -n data-generator get deployment recommendation-app-data
kubectl -n data-generator logs -l app=recommendation-app-data
```

### Tag Operations

```bash
# Create a tag
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" -d '{
    "name": "pii",
    "comment": "Personally identifiable information",
    "properties": {}
}' http://localhost:8090/api/metalakes/demolake/tags

# List all tags with details
curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  'http://localhost:8090/api/metalakes/demolake/tags?details=true'

# Attach tags to a topic
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" -d '{
    "tagsToAdd": ["pii", "prod"],
    "tagsToRemove": []
}' http://localhost:8090/api/metalakes/demolake/catalogs/my_cluster_catalog/schemas/default/topics/pii-topic-1/tags

# List objects with a specific tag
curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  http://localhost:8090/api/metalakes/demolake/tags/pii/objects

# Four tags are created by setup.sh:
# - dev (tier: 3)
# - staging (tier: 2)
# - prod (tier: 1)
# - pii (no tier)
```

### Debugging

```bash
# Check Gravitino deployment status
kubectl -n metadata get deployment gravitino
kubectl -n metadata logs -l app=gravitino

# Check Kafka cluster status
kubectl -n kafka get kafka my-cluster
kubectl -n kafka get kafkatopic

# Check MinIO tenant status
kubectl -n minio-tenant get tenants.minio.min.io myminio

# Check Apicurio Registry status
kubectl -n registry get deployment apicurio-registry
kubectl -n registry logs -l app=apicurio-registry

# Check Data Generator status
kubectl -n data-generator get deployment recommendation-app-data
kubectl -n data-generator logs -l app=recommendation-app-data

# Check PostgreSQL status
kubectl -n postgres get deployment postgres
kubectl -n postgres logs -l app=postgres
```

## Configuration Files

### Shared Configuration

All installation scripts source `setup/common.sh` which defines:
- Color codes for terminal output (RED, GREEN, YELLOW, BLUE, NC)
- Namespace names: `GRAVITINO_NAMESPACE="metadata"`, `KAFKA_NAMESPACE="kafka"`, `MINIO_OPERATOR_NAMESPACE="minio-operator"`, `MINIO_TENANT_NAMESPACE="minio-tenant"`, `POSTGRES_NAMESPACE="postgres"`, `APICURIO_NAMESPACE="registry"`
- Kafka cluster name: `KAFKA_CLUSTER_NAME="my-cluster"`
- Metalake name: `METALAKE="demolake"`
- Helper function: `check_prerequisite()` for validating required commands

When modifying namespaces, cluster names, or the metalake name, update `common.sh` to maintain consistency across all scripts.

### MinIO Setup

MinIO uses kustomize for deployment:
- `setup/minio/operator/kustomization.yaml`: MinIO operator
- `setup/minio/tenant/kustomization.yaml`: MinIO tenant configuration
- `setup/minio/buckets/bucket-list-configmap.yaml`: Defines buckets to create

Buckets created during setup:
- `test-bucket`: General testing bucket
- `product-csvs`: Stores product inventory CSV files
- `iceberg-warehouse`: Storage for Apache Iceberg tables

The `setup/example-resources/create-minio-buckets.sh` script creates these buckets via a Kubernetes Job. MinIO service account credentials are created during installation by a Kubernetes Job and stored in the `gravitino-minio-credentials` secret in the `metadata` namespace.

### Fileset Catalog Configuration

The `setup/example-resources/create-fileset-catalog.sh` script creates an S3-backed fileset catalog. Key properties:
- Catalog name: `product_files` (FILESET type)
- Schema name: `product_schema` at location `s3a://product-csvs/schema`
- Fileset name: `product_inventory_fileset` at `s3a://product-csvs/schema/product-data`
- Credentials: Retrieved from Kubernetes secret `gravitino-minio-credentials` (created during install) and exported as environment variables `GRAVITINO_S3_ACCESS_KEY` and `GRAVITINO_S3_SECRET_KEY`
- S3 endpoint: `https://myminio-hl.minio-tenant.svc.cluster.local:9000`
- Uses S3A filesystem with path-style access and SSL enabled

### PostgreSQL Catalog Configuration

The `setup/example-resources/create-relational-catalog.sh` script creates a PostgreSQL catalog:
- Catalog name: `postgres_catalog` (RELATIONAL type, provider: jdbc-postgresql)
- Schema name: `public`
- JDBC URL: `jdbc:postgresql://postgres.postgres.svc.cluster.local:5432/testdb`
- Credentials: user `admin`, password `admin`
- Creates table `product_inventory` with columns: id, category, price, quantity
- Data loaded from `setup/data/productInventory.csv` via `create-tables.sh`

### Apicurio Registry Configuration

Apicurio Registry is deployed in the `registry` namespace via kustomize:
- Deployment configuration: `setup/apicurio-registry/apicurio-registry-deployment.yaml`
- Service configuration: `setup/apicurio-registry/apicurio-registry-service.yaml`
- Namespace: `setup/apicurio-registry/apicurio-registry-namespace.yaml`
- Kustomization: `setup/apicurio-registry/kustomization.yaml`

Key properties:
- Image: `apicurio/apicurio-registry-mem:latest-release` (in-memory storage)
- Service name: `apicurio-registry-service`
- Service port: 8080 (targetPort: 8080)
- API endpoint: `http://apicurio-registry-service.registry.svc:8080/apis/registry/v2`
- Storage: Ephemeral (in-memory), schemas are lost on pod restart

### Data Generator Configuration

The data generator application is deployed in the `data-generator` namespace via kustomize:
- Deployment configuration: `setup/data-generator-app/data-gen-deployment.yaml`
- Namespace: `setup/data-generator-app/data-gen-namespace.yaml`
- Kustomization: `setup/data-generator-app/kustomization.yaml`

Key properties:
- Image: `quay.io/streamshub/flink-examples-data-generator:main`
- Deployment name: `recommendation-app-data`
- Kafka bootstrap servers: `my-cluster-kafka-bootstrap.kafka.svc:9092`
- Data types generated: `clickStream,sales,internationalSales`
- Apicurio Registry URL: `http://apicurio-registry-service.registry.svc:8080/apis/registry/v2`
- Uses Apicurio for schema management: `USE_APICURIO_REGISTRY=true`

### Iceberg Catalog Configuration

The `setup/example-resources/create-iceberg-catalog.sh` script creates an Apache Iceberg REST catalog:
- Catalog name: `iceberg_rest_catalog` (RELATIONAL type, provider: lakehouse-iceberg)
- Schema name: `iceberg_schema`
- REST URI: `http://gravitino-iceberg-rest-server.metadata.svc.cluster.local:9001/iceberg/` (includes `/iceberg/` path required by Iceberg REST API spec)
- Warehouse location: `s3://iceberg-warehouse` (note: uses `s3://` protocol, not `s3a://`)
- **Catalog backend**: JDBC (PostgreSQL) for persistent metadata storage
  - JDBC URL: `jdbc:postgresql://postgres.postgres.svc.cluster.local:5432/testdb`
  - Database credentials: user `admin`, password `admin`
  - JDBC driver: `org.postgresql.Driver` (PostgreSQL JDBC driver v42.7.8)
  - **Driver installation**: An initContainer automatically downloads the PostgreSQL JDBC driver at pod startup
    - The driver JAR is downloaded from `https://jdbc.postgresql.org/download/postgresql-42.7.8.jar`
    - Mounted into the container at `/root/gravitino-iceberg-rest-server/libs/postgresql.jar`
    - Configuration file: `setup/gravitino-install/patch-iceberg-rest-deployment.yaml`
  - Backend configuration file: `setup/gravitino-install/patch-iceberg-rest-configmap.yaml`
- Uses MinIO bucket `iceberg-warehouse` for table storage
- **S3 credentials**: Automatically injected at startup from Kubernetes secret `gravitino-minio-credentials`
  - Credentials are mounted into the iceberg-rest-server pod at `/etc/minio-credentials`
  - Init script reads credentials and appends them to `gravitino-iceberg-rest-server.conf`
  - No manual credential configuration required
- **AWS SDK dependencies**: Iceberg AWS bundle (v1.6.1) automatically downloaded via initContainer
  - Both Gravitino main server and Iceberg REST server download the bundle at startup
  - Provides S3FileIO and AWS SDK classes for S3/MinIO operations
  - JAR mounted at `/root/gravitino/libs/iceberg-aws-bundle.jar` (main server) and `/root/gravitino-iceberg-rest-server/libs/iceberg-aws-bundle.jar` (REST server)
- **PostgreSQL dependency**: The PostgreSQL database must be running before deploying the Iceberg REST server, as it stores catalog metadata

### Setup Scripts

The `setup/example-resources/` directory contains scripts for configuring catalogs and data:

**Kafka Setup:**
- `example-topics.yaml`: Defines four Kafka topics (dev-topic-1, staging-topic-1, prod-topic-1, pii-topic-1)
- `setup-kafka.sh`: Creates Kafka topics, catalog, tags, and attaches tags to topics

**PostgreSQL Setup:**
- `create-tables.sh`: Creates PostgreSQL tables and loads CSV data
- `create-relational-catalog.sh`: Creates Gravitino catalog for PostgreSQL

**MinIO Setup:**
- `setup-minio-tenant.sh`: Deploys MinIO tenant via kustomize
- `create-minio-buckets.sh`: Creates S3 buckets via Kubernetes Job
- `create-minio-service-account.sh`: Manual script for credential rotation (not used in automated setup)
- `upload-minio-data.sh`: Uploads CSV files to MinIO buckets
- `create-fileset-catalog.sh`: Creates Gravitino fileset catalog for S3/MinIO

**Iceberg Setup:**
- `create-iceberg-catalog.sh`: Creates Gravitino catalog for Apache Iceberg REST

**Tag Management:**
- `create-tags.sh`: Creates environment tags (dev, staging, prod, pii)
- `attach-tags.sh`: Attaches tags to Kafka topics

## Prerequisites

- Kubernetes 1.18+ (tested with Minikube: `minikube start --cpus 8 --memory 28G --disk-size 50g`)
- kubectl 1.18+
- Helm 3.5+
- PostgreSQL client (`psql`) for database operations
- MinIO client (`mc`) for S3 operations
- `jq` for JSON processing in scripts

The `install.sh` script validates these prerequisites (except `mc`) before starting installation.

## Key Implementation Notes

- The Gravitino submodule at `setup/gravitino/` is from the Apache Gravitino repository
- Manifests are generated from Gravitino Helm charts, not applied directly with Helm
- Port-forwarding is required for local API access (setup.sh creates them automatically and displays PIDs)
- The metalake name is `demolake` (configurable in `setup/common.sh`)
- Three catalog types are demonstrated:
  - **MESSAGING**: Kafka topics via Strimzi
  - **FILESET**: S3/MinIO files
  - **RELATIONAL**: PostgreSQL tables and Iceberg tables
- Tags (dev, staging, prod, pii) are created and attached to objects with properties like tier levels
- Kafka topics use Strimzi CRDs (`KafkaTopic`) managed by the Strimzi operator
- MinIO buckets (`test-bucket`, `product-csvs`, `iceberg-warehouse`) are created via Kubernetes Job
- **Credential Management**: MinIO service account credentials are created during installation via shell script and stored in secret `gravitino-minio-credentials`
  - Script `setup/gravitino-install/create-minio-credentials-secret.sh` creates service account using `mc` and stores credentials in Kubernetes
  - Iceberg REST server automatically receives credentials via secret mount and runtime injection
  - Setup scripts retrieve credentials from the secret for fileset catalog creation
  - Single source of truth for S3/MinIO credentials across all components
- PostgreSQL data is loaded from `setup/data/productInventory.csv`
- All scripts check for existing resources before creating new ones (idempotent operations)
- Installation uses phased approach: Kafka/MinIO/PostgreSQL/Apicurio in parallel, then Gravitino sequentially after MinIO completes
- **Apicurio Registry**: Schema registry deployed in `registry` namespace, provides schema management for Kafka messages
  - Service accessible at `apicurio-registry-service.registry.svc:8080`
  - Uses in-memory storage (ephemeral)
- **Data Generator Application**: Generates sample data (clickStream, sales, internationalSales) and publishes to Kafka topics
  - Deployed in `data-generator` namespace
  - Configured to use Apicurio Registry for schema management
  - Connects to Kafka cluster at `my-cluster-kafka-bootstrap.kafka.svc:9092`
  - Deployment name: `recommendation-app-data`

