#!/bin/bash

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "name": "dev", 
        "comment": "This object is in the development environment", 
        "properties": {"tier": "3"}
    }' http://localhost:8090/api/metalakes/strimzi_kafka/tags

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "name": "staging", 
        "comment": "This object is in the staging environment", 
        "properties": {"tier": "2"}
    }' http://localhost:8090/api/metalakes/strimzi_kafka/tags

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "name": "prod", 
        "comment": "This object is in the production environment", 
        "properties": {"tier": "1"}
    }' http://localhost:8090/api/metalakes/strimzi_kafka/tags

curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "name": "pii", 
        "comment": "This object is associated with personally identifiable information"
    }' http://localhost:8090/api/metalakes/strimzi_kafka/tags

curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
'http://localhost:8090/api/metalakes/strimzi_kafka/tags?details=true'