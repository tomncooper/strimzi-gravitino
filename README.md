# Apache Gravitino with Strimzi managed Kafka

[Apache Gravitino](https://gravitino.apache.org/) is an open-source unified metadata management platform that provides a centralized way to discover, manage, and govern metadata across various data systems and storage engines. 

This repo provides an example of how to deploy a basic Gravitino setup with a Strimzi managed Kafka cluster. 
It then walks through the various metadata management operations, related to Kafka.

## Prerequisites

- Kubernetes cluster (1.18+) (eg Minikube)
- Helm (3.5+)
- kubectl (1.18+)

## Installation

This installation assumes you have a working Kubernetes cluster, with adequate resources (minimum 6 CPUS and 16GB of RAM) and have `kubectl` and `helm` installed and configured to access your cluster.

### Install Gravitino 

1. Run the manifest generation script to create the necessary Kubernetes resources to install Gravitino. The first argument is the git-ref (branch, tag, commit) of the Gravitino release you want to install. The script will create a `manifests/gravitino` directory and place the generated manifest in there:
   ```shell
   ./gravitino-manifests.sh v1.0.0
   ```
1. Create the `metadata` namespace (you can specify a different namespace with the second argument to the `gravitino-manifests.sh` script):
   ```shell
   kubectl create namespace metadata
   ```
1. Apply the generated manifest to your Kubernetes cluster:
   ```shell
   kubectl apply -f manifests/gravitino/gravitino-manifests-<helm-chart-version>.yaml
   ```
1. To allow local access to the REST API and the web-UI, port-forward the service:
   ```shell
   kubectl -n metadata port-forward svc/gravitino 8090:8090 
   ```

### Install Strimzi Kafka via Helm

1. Install the Strimzi Kafka operator:
   ```shell
   helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator -n kafka --create-namespace
   ```
1. Install a Kafka cluster:
   ```shell
   kubectl apply -f https://strimzi.io/examples/latest/kafka/kafka-single-node.yaml -n kafka 
   ```
   This will create a Kafka cluster, called `my-cluster` in the `kafka` namespace.
1. Add Kafka topics to the cluster. You can do this by creating `KafkaTopic` CRs in the `kafka` namespace. Example resource definitions can be found in the `example-topics.yaml` file in the `example-resources` directory:
    ```shell
    kubectl -n kafka apply -f example-resources/example-topics.yaml
    ```

## Setup Gravitino

1. Create a metalake to house your Kafka cluster catalogs:
    ```shell
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "name":"strimzi_kafka",
        "comment":"This metalake holds all Strimzi related metadata",
        "properties":{}
    }' http://localhost:8090/api/metalakes
    ```
1. Add the Kafka Cluster as a catalog to Gravitino:
    ```shell
    curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "name": "my_cluster_catalog",
        "type": "MESSAGING",
        "comment": "Catalog for the my_cluster Kafka cluster",
        "provider": "kafka",
        "properties": {
            "bootstrap.servers": "my-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092"
        }
    }' http://localhost:8090/api/metalakes/strimzi_kafka/catalogs
    ```
1. You can check the newly added Kafka Catalog in the web UI by visiting `http://localhost:8090` or via an API call:
   ```shell
    curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" \
    http://localhost:8090/api/metalakes/strimzi_kafka/catalogs/my_cluster_catalog/schemas/default/topics
   ```

## Using Gravitino

You can now use the operations described in the Gravitino Kafka Catalog [documentation](https://gravitino.apache.org/docs/0.9.1/manage-massaging-metadata-using-gravitino/) to manage the metadata associated with the Strimzi managed Kafka cluster.

### Tagging Metadata Objects

In Gravitino, you can create [tags](https://gravitino.apache.org/docs/0.9.1/manage-tags-in-gravitino/) within a metalake, catalog or schema and then attach them to metadata objects.

These tags are hierarchical, meaning that a tag applied to a catalog will be attached to all metadata objects within that catalog.

#### Creating Tags

You create tags at the metalake level:

```shell
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
    -H "Content-Type: application/json" -d '{
        "name": "dev", 
        "comment": "This object is in the development environment", 
        "properties": {"tier": "3"}
    }' http://localhost:8090/api/metalakes/strimzi_kafka/tags
```

Note: There is a `create-tags.sh` script in the `example-resources` directory which will create the `dev` tag above as well as the `staging`, `prod`, and `pii` tags.

You can then view them using:
```shell
curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
'http://localhost:8090/api/metalakes/strimzi_kafka/tags?details=true'
```

#### Attaching Tags to Metadata Objects

We can now attach the tags we created to metadata objects within that metalake:

```shell
curl -X POST -H "Accept: application/vnd.gravitino.v1+json" \
-H "Content-Type: application/json" -d '{
  "tagsToAdd": ["pii"]
}' http://localhost:8090/api/metalakes/strimzi_kafka/objects/topic/my_cluster_catalog.default.pii-topic-1/tags
```

Note: There is a `attach-tags.sh` script in the `example-resources` directory which will attach the appropriate tags to the Kafka topics created earlier, based on their environment (dev, staging, prod) and pii status.

You can list all metadata objects with a given tag by using:
```shell
curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
http://localhost:8090/api/metalakes/strimzi_kafka/tags/pii/objects
```
