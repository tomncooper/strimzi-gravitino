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

### Gravitino Hierarchy

Gravitino organizes metadata in a hierarchy:
- **Metalake** (`strimzi_kafka`): Top-level container for all metadata
- **Catalogs**: Collections for specific data systems (Kafka, S3 filesets, etc.)
  - `my_cluster_catalog`: MESSAGING catalog for Kafka topics
  - `product_files_catalog_2`: FILESET catalog for S3/MinIO data
- **Schemas**: Logical groupings within catalogs
- **Objects**: Actual data objects (topics, filesets, tables)
- **Tags**: Hierarchical metadata labels applied to objects

### Installation Flow

The `gravitino-manifests.sh` script extracts Helm manifests from the Gravitino git submodule at `setup/gravitino/`. It checks out a specific version tag, packages the Helm chart, and generates Kubernetes manifests with kustomize. This approach avoids runtime Helm dependencies.

## Common Commands

### Initial Setup

```bash
# Full automated installation (requires 6 CPUs, 16GB RAM minimum)
./setup/install.sh

# Setup metadata, topics, tags, and data uploads
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
    "name":"strimzi_kafka",
    "comment":"This metalake holds all Strimzi related metadata",
    "properties":{}
}' http://localhost:8090/api/metalakes

# Create Kafka catalog
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
  -H "Content-Type: application/json" -d '{
    "name": "my_cluster_catalog",
    "type": "MESSAGING",
    "provider": "kafka",
    "properties": {
        "bootstrap.servers": "my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092"
    }
}' http://localhost:8090/api/metalakes/strimzi_kafka/catalogs

# List tags with details
curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  'http://localhost:8090/api/metalakes/strimzi_kafka/tags?details=true'

# List objects with a specific tag
curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  http://localhost:8090/api/metalakes/strimzi_kafka/tags/pii/objects
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
```

## Configuration Files

### Shared Configuration

All installation scripts source `setup/common.sh` which defines:
- Color codes for terminal output
- Namespace names for all components
- Kafka cluster name
- Other shared constants

When modifying namespaces or cluster names, update `common.sh` to maintain consistency.

### MinIO Setup

MinIO uses kustomize for deployment:
- `setup/minio/operator/kustomization.yaml`: MinIO operator
- `setup/minio/tenant/kustomization.yaml`: MinIO tenant configuration
- `setup/minio/buckets/`: Bucket creation via Kubernetes Job

### Fileset Catalog Configuration

The `setup/example-resources/create-fileset.sh` script creates an S3-backed fileset catalog. Key properties:
- Base64-encoded credentials: `Y29uc29sZQ==` (console) and `Y29uc29zZTEyMw==` (consoze123)
- S3 endpoint points to MinIO service: `https://myminio-hl.minio-tenant.svc.cluster.local:9000`
- Uses S3A filesystem with path-style access
- SSL disabled for internal cluster communication

## Prerequisites

- Kubernetes 1.18+ (tested with Minikube: `minikube start --cpus 8 --memory 28G --disk-size 50g`)
- kubectl 1.18+
- Helm 3.5+
- MinIO client (`mc`) for S3 operations
- `jq` for JSON processing in scripts

## Key Implementation Notes

- The Gravitino submodule at `setup/gravitino/` is from the Apache Gravitino repository
- Manifests are generated from Gravitino Helm charts, not applied directly with Helm
- Port-forwarding is required for local API access (scripts handle this automatically)
- Tags are hierarchical and can be applied at catalog, schema, or object level
- Kafka topics use Strimzi CRDs (`KafkaTopic`) managed by the Strimzi operator
- MinIO buckets are created via a Kubernetes Job that runs the MinIO client

