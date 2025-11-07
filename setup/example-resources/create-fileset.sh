#!/bin/bash

METALAKE="strimzi_kafka"
FILESET_CATALOG_NAME="product_files_catalog"
FILESET_SCHEMA_NAME="product_schema"

# Check if catalog exists
echo "Checking if catalog '${FILESET_CATALOG_NAME}' exists..."
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}" 2>/dev/null | grep -q "\"name\":\"${FILESET_CATALOG_NAME}\""; then
    echo "✓ Catalog '${FILESET_CATALOG_NAME}' already exists"
else
    echo "Creating catalog '${FILESET_CATALOG_NAME}'..."
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg name "${FILESET_CATALOG_NAME}" \
      '{
        name: $name,
        type: "FILESET",
        comment: "This is a S3 fileset catalog",
        properties: {
          location: "s3a://product-csvs",
          "s3-access-key-id": "Y29uc29sZQ==",
          "s3-secret-access-key": "Y29uc29zZTEyMw==",
          "s3-endpoint": "https://myminio-hl.minio-tenant.svc.cluster.local:9000",
          "filesystem-providers": "s3"
        }
      }')" \
    http://localhost:8090/api/metalakes/${METALAKE}/catalogs
    echo ""
fi

echo "Waiting for catalog to be fully registered..."
sleep 10

# Check if schema exists
echo "Checking if schema '${FILESET_SCHEMA_NAME}' exists..."
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}/schemas/${FILESET_SCHEMA_NAME}" 2>/dev/null | grep -q "\"name\":\"${FILESET_SCHEMA_NAME}\""; then
    echo "✓ Schema '${FILESET_SCHEMA_NAME}' already exists"
else
    echo "Creating schema '${FILESET_SCHEMA_NAME}'..."
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg name "${FILESET_SCHEMA_NAME}" \
      '{
        name: $name,
        comment: "This is a S3 schema",
        properties: {
          location: "s3a://product-csvs/schema"
        }
      }')" \
    http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${FILESET_CATALOG_NAME}/schemas
    echo ""
fi

echo "✓ Fileset catalog and schema setup complete"