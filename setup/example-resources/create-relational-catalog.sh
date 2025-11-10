#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/../common.sh"

POSTGRES_CATALOG_NAME="postgres_catalog"
POSTGRES_SCHEMA_NAME="public"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Creating Gravitino PostgreSQL Catalog ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if catalog exists
echo -e "${YELLOW}Checking if catalog '${POSTGRES_CATALOG_NAME}' exists...${NC}"
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${POSTGRES_CATALOG_NAME}" 2>/dev/null | grep -q "\"name\":\"${POSTGRES_CATALOG_NAME}\""; then
    echo -e "${GREEN}✓ Catalog '${POSTGRES_CATALOG_NAME}' already exists${NC}"
else
    echo -e "${YELLOW}Creating catalog '${POSTGRES_CATALOG_NAME}'...${NC}"
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "'"${POSTGRES_CATALOG_NAME}"'",
        "type": "RELATIONAL",
        "comment": "PostgreSQL catalog for product inventory",
        "provider": "jdbc-postgresql",
        "properties": {
            "jdbc-url": "jdbc:postgresql://postgres.'"${POSTGRES_NAMESPACE}"'.svc.cluster.local:5432/testdb",
            "jdbc-driver": "org.postgresql.Driver",
            "jdbc-database": "testdb",
            "jdbc-user": "admin",
            "jdbc-password": "admin"
        }
    }' http://localhost:8090/api/metalakes/${METALAKE}/catalogs
    echo ""
    echo -e "${GREEN}✓ Catalog '${POSTGRES_CATALOG_NAME}' created${NC}"
fi
echo ""

# Check if schema exists
echo -e "${YELLOW}Checking if schema '${POSTGRES_SCHEMA_NAME}' exists...${NC}"
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${POSTGRES_CATALOG_NAME}/schemas/${POSTGRES_SCHEMA_NAME}" 2>/dev/null | grep -q "\"name\":\"${POSTGRES_SCHEMA_NAME}\""; then
    echo -e "${GREEN}✓ Schema '${POSTGRES_SCHEMA_NAME}' already exists${NC}"
else
    echo -e "${YELLOW}Creating schema '${POSTGRES_SCHEMA_NAME}'...${NC}"
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "'"${POSTGRES_SCHEMA_NAME}"'",
        "comment": "PostgreSQL public schema"
    }' http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${POSTGRES_CATALOG_NAME}/schemas
    echo ""
    echo -e "${GREEN}✓ Schema '${POSTGRES_SCHEMA_NAME}' created${NC}"
fi
echo ""

# Check if table exists
echo -e "${YELLOW}Checking if table 'product_inventory' exists...${NC}"
if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    "http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${POSTGRES_CATALOG_NAME}/schemas/${POSTGRES_SCHEMA_NAME}/tables/product_inventory" 2>/dev/null | grep -q "\"name\":\"product_inventory\""; then
    echo -e "${GREEN}✓ Table 'product_inventory' already exists${NC}"
else
    echo -e "${YELLOW}Creating table 'product_inventory'...${NC}"
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "product_inventory",
        "comment": "Product inventory table",
        "columns": [
            {
                "name": "id",
                "type": "integer",
                "comment": "Product ID",
                "nullable": false
            },
            {
                "name": "category",
                "type": "varchar(50)",
                "comment": "Product category",
                "nullable": false
            },
            {
                "name": "price",
                "type": "integer",
                "comment": "Product price",
                "nullable": false
            },
            {
                "name": "quantity",
                "type": "integer",
                "comment": "Product quantity",
                "nullable": false
            }
        ]
    }' http://localhost:8090/api/metalakes/${METALAKE}/catalogs/${POSTGRES_CATALOG_NAME}/schemas/${POSTGRES_SCHEMA_NAME}/tables
    echo ""
    echo -e "${GREEN}✓ Table 'product_inventory' created${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Gravitino PostgreSQL Catalog Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
