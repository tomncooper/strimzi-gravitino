#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration
source "${SCRIPT_DIR}/../common.sh"

# PostgreSQL connection details
PGHOST="localhost"
PGPORT="5432"
PGDATABASE="testdb"
PGUSER="admin"
PGPASSWORD="admin"

export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Creating PostgreSQL Tables ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if psql is installed
if ! command -v psql &> /dev/null; then
    echo -e "${RED}ERROR: psql (PostgreSQL client) is not installed${NC}"
    echo -e "${RED}Please install it from: https://www.postgresql.org/download/${NC}"
    exit 1
fi

# Check if port-forward is running
if ! pgrep -f "port-forward.*postgres.*5432:5432" > /dev/null; then
    echo -e "${RED}ERROR: Postgres port-forward is not running${NC}"
    echo -e "${YELLOW}Please run: kubectl -n ${POSTGRES_NAMESPACE} port-forward svc/postgres 5432:5432${NC}"
    exit 1
fi

echo -e "${YELLOW}Testing PostgreSQL connection...${NC}"
if ! psql -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Cannot connect to PostgreSQL${NC}"
    echo -e "${RED}Please ensure the port-forward is running and PostgreSQL is ready${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL connection successful${NC}"
echo ""

# Create product_inventory table
echo -e "${YELLOW}Creating product_inventory table...${NC}"
psql << 'EOF'
DROP TABLE IF EXISTS product_inventory;

CREATE TABLE product_inventory (
    id INTEGER PRIMARY KEY,
    category VARCHAR(50) NOT NULL,
    price INTEGER NOT NULL,
    quantity INTEGER NOT NULL
);

CREATE INDEX idx_category ON product_inventory(category);
CREATE INDEX idx_price ON product_inventory(price);
EOF

echo -e "${GREEN}✓ product_inventory table created${NC}"
echo ""

# Load data from CSV
echo -e "${YELLOW}Loading data from productInventory.csv...${NC}"
psql -c "\\COPY product_inventory FROM '${SCRIPT_DIR}/../data/productInventory.csv' WITH (FORMAT csv, DELIMITER ',')"

# Get row count
ROW_COUNT=$(psql -t -c "SELECT COUNT(*) FROM product_inventory;" | xargs)
echo -e "${GREEN}✓ Loaded ${ROW_COUNT} rows into product_inventory table${NC}"
echo ""

# Display some statistics
echo -e "${YELLOW}Table statistics:${NC}"
psql << 'EOF'
SELECT
    category,
    COUNT(*) as product_count,
    AVG(price)::INTEGER as avg_price,
    AVG(quantity)::INTEGER as avg_quantity
FROM product_inventory
GROUP BY category
ORDER BY category;
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PostgreSQL Tables Created Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
