#!/bin/bash

set -e  # Exit on any error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/../common.sh"

ICEBERG_CATALOG_NAME="iceberg_rest_catalog"
ICEBERG_SCHEMA_NAME="iceberg_schema"
ICEBERG_REST_URI="http://gravitino-iceberg-rest-server.metadata.svc.cluster.local:9001/iceberg/"

# Check if catalog exists
echo "Checking if catalog '${ICEBERG_CATALOG_NAME}' exists..."
CATALOG_CHECK=$(curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${ICEBERG_CATALOG_NAME}" 2>/dev/null)

if echo "$CATALOG_CHECK" | grep -q "\"name\":\"${ICEBERG_CATALOG_NAME}\""; then
    echo "✓ Catalog '${ICEBERG_CATALOG_NAME}' already exists"
else
    echo "Creating catalog '${ICEBERG_CATALOG_NAME}'..."
    CATALOG_RESPONSE=$(curl -s -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg name "${ICEBERG_CATALOG_NAME}" \
      --arg uri "${ICEBERG_REST_URI}" \
      '{
        name: $name,
        type: "RELATIONAL",
        comment: "Iceberg REST catalog",
        provider: "lakehouse-iceberg",
        properties: {
          "uri": $uri,
          "catalog-backend": "rest"
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
fi

# Check if schema exists
echo "Checking if schema '${ICEBERG_SCHEMA_NAME}' exists..."
SCHEMA_CHECK=$(curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${ICEBERG_CATALOG_NAME}/schemas/${ICEBERG_SCHEMA_NAME}" 2>/dev/null)

if echo "$SCHEMA_CHECK" | grep -q "\"name\":\"${ICEBERG_SCHEMA_NAME}\""; then
    echo "✓ Schema '${ICEBERG_SCHEMA_NAME}' already exists"
else
    echo "Creating schema '${ICEBERG_SCHEMA_NAME}'..."
    SCHEMA_RESPONSE=$(curl -s -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg name "${ICEBERG_SCHEMA_NAME}" \
      '{
        name: $name,
        comment: "Iceberg schema for product data",
        properties: {}
      }')" \
    http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${ICEBERG_CATALOG_NAME}/schemas)

    echo "$SCHEMA_RESPONSE" | jq

    if echo "$SCHEMA_RESPONSE" | jq -e '.code == 0' > /dev/null 2>&1; then
        echo "✓ Schema created successfully"
    else
        echo "✗ Failed to create schema"
        exit 1
    fi
    echo ""
fi

echo "✓ Iceberg catalog setup complete"
