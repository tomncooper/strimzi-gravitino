#!/bin/bash

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "tagsToAdd": ["dev"]
    }' http://localhost:8090/api/metalakes/strimzi_kafka/objects/topic/my_cluster_catalog.default.dev-topic-1/tags

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "tagsToAdd": ["staging"]
    }' http://localhost:8090/api/metalakes/strimzi_kafka/objects/topic/my_cluster_catalog.default.staging-topic-1/tags

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "tagsToAdd": ["prod"]
    }' http://localhost:8090/api/metalakes/strimzi_kafka/objects/topic/my_cluster_catalog.default.prod-topic-1/tags

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "tagsToAdd": ["prod", "pii"]
    }' http://localhost:8090/api/metalakes/strimzi_kafka/objects/topic/my_cluster_catalog.default.pii-topic-1/tags