#!/bin/bash

set -e  # Exit on any error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/../common.sh"

FILESET_CATALOG_NAME="product_files"
FILESET_SCHEMA_NAME="product_schema"
FILESET_NAME="product_inventory_fileset"
BUCKET_NAME="product-csvs"
SCHEMA_FOLDER_NAME="schema"

# Check for required MinIO credentials
if [ -z "$GRAVITINO_S3_ACCESS_KEY" ] || [ -z "$GRAVITINO_S3_SECRET_KEY" ]; then
    echo "Error: MinIO credentials not set. Please set GRAVITINO_S3_ACCESS_KEY and GRAVITINO_S3_SECRET_KEY environment variables"
    exit 1
fi

# Check if catalog exists
echo "Checking if catalog '${FILESET_CATALOG_NAME}' exists..."
CATALOG_CHECK=$(curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}" 2>/dev/null)

if echo "$CATALOG_CHECK" | grep -q "\"name\":\"${FILESET_CATALOG_NAME}\""; then
    echo "✓ Catalog '${FILESET_CATALOG_NAME}' already exists"
else
    echo "Creating catalog '${FILESET_CATALOG_NAME}'..."
    CATALOG_RESPONSE=$(curl -s -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg name "${FILESET_CATALOG_NAME}" \
      --arg bucket_name "${BUCKET_NAME}" \
      --arg access_key "${GRAVITINO_S3_ACCESS_KEY}" \
      --arg secret_key "${GRAVITINO_S3_SECRET_KEY}" \
      '{
        name: $name,
        type: "FILESET",
        comment: "This is a S3 fileset catalog",
        properties: {
          location: ("s3a://" + $bucket_name),
          "s3-access-key-id": $access_key,
          "s3-secret-access-key": $secret_key,
          "s3-endpoint": "https://myminio-hl.minio-tenant.svc.cluster.local:9000",
          "filesystem-providers": "s3",
          "disable-filesystem-ops": "false",
          "gravitino.bypass.fs.s3a.path.style.access": "true",
          "gravitino.bypass.fs.s3a.connection.ssl.enabled": "true",
          "gravitino.bypass.fs.s3a.ssl.channel.mode": "default_jsse"
        }
      }')" \
    http://localhost:8090/api/metalakes/${METALAKE}/catalogs)
    
    echo "$CATALOG_RESPONSE" | jq
    
    if echo "$CATALOG_RESPONSE" | jq -e '.code == 0' > /dev/null 2>&1; then
        echo "✓ Catalog created successfully"
    else
        echo "✗ Failed to create catalog"
        exit 1
    fi
    echo ""
fi

# Check if schema exists
echo "Checking if schema '${FILESET_SCHEMA_NAME}' exists..."
SCHEMA_CHECK=$(curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}/schemas/${FILESET_SCHEMA_NAME}" 2>/dev/null)

if echo "$SCHEMA_CHECK" | grep -q "\"name\":\"${FILESET_SCHEMA_NAME}\""; then
    echo "✓ Schema '${FILESET_SCHEMA_NAME}' already exists"
else
    echo "Creating schema '${FILESET_SCHEMA_NAME}'..."
    SCHEMA_RESPONSE=$(curl -s -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg name "${FILESET_SCHEMA_NAME}" \
      --arg bucket_name "${BUCKET_NAME}" \
      --arg schema_location "${SCHEMA_FOLDER_NAME}" \
      '{
        name: $name,
        comment: "This is a S3 schema",
        properties: {
          location: ("s3a://" + $bucket_name + "/" + $schema_location)
        }
      }')" \
    http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}/schemas)
    
    echo "$SCHEMA_RESPONSE" | jq
    
    if echo "$SCHEMA_RESPONSE" | jq -e '.code == 0' > /dev/null 2>&1; then
        echo "✓ Schema created successfully"
    else
        echo "✗ Failed to create schema"
        exit 1
    fi
    echo ""
fi

# Check if fileset exists
echo "Checking if fileset ${FILESET_NAME} exists..."
FILESET_CHECK=$(curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}/schemas/${FILESET_SCHEMA_NAME}/filesets/${FILESET_NAME}" 2>/dev/null)

if echo "$FILESET_CHECK" | grep -q "\"name\":\"${FILESET_NAME}\""; then
    echo "✓ Fileset ${FILESET_NAME} already exists"
else
    echo "Creating fileset '${FILESET_NAME}'..."
    FILESET_RESPONSE=$(curl -s -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg name "${FILESET_NAME}" \
      --arg bucket_name "${BUCKET_NAME}" \
      --arg schema_location "${SCHEMA_FOLDER_NAME}" \
    '{
      name: $name,
      comment: "Fileset for all product data",
      type: "MANAGED",
      storageLocation: ("s3a://" + $bucket_name + "/" + $schema_location + "/product-data")
  }')" http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}/schemas/${FILESET_SCHEMA_NAME}/filesets)
    
    echo "$FILESET_RESPONSE" | jq
    
    if echo "$FILESET_RESPONSE" | jq -e '.code == 0' > /dev/null 2>&1; then
        echo "✓ Fileset created successfully"
    else
        echo "✗ Failed to create fileset"
        exit 1
    fi
fi

echo "✓ Fileset catalog and schema setup complete"