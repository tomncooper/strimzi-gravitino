#!/bin/bash

# Function to create tag if it doesn't exist
create_tag_if_not_exists() {
    local tag_name=$1
    local tag_comment=$2
    local tag_properties=$3
    
    # Check if tag exists
    if curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
        "http://localhost:8090/api/metalakes/strimzi_kafka/tags/${tag_name}" 2>/dev/null | grep -q "\"name\":\"${tag_name}\""; then
        echo "✓ Tag '${tag_name}' already exists"
    else
        echo "Creating tag '${tag_name}'..."
        curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
            -H "Content-Type: application/json" -d "{
                \"name\": \"${tag_name}\",
                \"comment\": \"${tag_comment}\",
                \"properties\": ${tag_properties}
            }" http://localhost:8090/api/metalakes/strimzi_kafka/tags
        echo ""
    fi
}

# Create tags
create_tag_if_not_exists "dev" "This object is in the development environment" '{"tier": "3"}'
create_tag_if_not_exists "staging" "This object is in the staging environment" '{"tier": "2"}'
create_tag_if_not_exists "prod" "This object is in the production environment" '{"tier": "1"}'
create_tag_if_not_exists "pii" "This object is associated with personally identifiable information" ''
