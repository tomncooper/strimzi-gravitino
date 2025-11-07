#!/bin/bash

METALAKE = "strimzi_kafka"

# Function to attach tags to an object if not already associated
attach_tags_if_not_exists() {
    local object_path=$1
    shift
    local tags=("$@")
    
    # Get currently associated tags for the object
    echo "Checking tags for object: $object_path"
    current_tags=$(curl -s -X GET -H "Accept: application/vnd.gravitino.v1+json" \
        "http://localhost:8090/api/metalakes/${METALAKE}/objects/topic/${object_path}/tags" 2>/dev/null)
    
    # Build array of tags to add
    tags_to_add=()
    for tag in "${tags[@]}"; do
        if echo "$current_tags" | grep -q "\"$tag\""; then
            echo "✓ Tag '$tag' already associated with $object_path"
        else
            tags_to_add+=("$tag")
        fi
    done
    
    # If there are tags to add, make the API call
    if [ ${#tags_to_add[@]} -gt 0 ]; then
        echo "Attaching tags [${tags_to_add[*]}] to $object_path..."
        
        # Build JSON array of tags
        json_tags=$(printf ',"%s"' "${tags_to_add[@]}")
        json_tags="[${json_tags:1}]"
        
        curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
            -H "Content-Type: application/json" -d "{
                \"tagsToAdd\": $json_tags
            }" "http://localhost:8090/api/metalakes/${METALAKE}/objects/topic/${object_path}/tags"
        echo ""
    else
        echo "✓ All tags already associated with $object_path"
    fi
    echo ""
}

# Attach tags to topics
attach_tags_if_not_exists "my_cluster_catalog.default.dev-topic-1" "dev"
attach_tags_if_not_exists "my_cluster_catalog.default.staging-topic-1" "staging"
attach_tags_if_not_exists "my_cluster_catalog.default.prod-topic-1" "prod"
attach_tags_if_not_exists "my_cluster_catalog.default.pii-topic-1" "prod" "pii"