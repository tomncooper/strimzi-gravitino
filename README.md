# Apache Gravitino with Strimzi managed Kafka

[Apache Gravitino](https://gravitino.apache.org/) is an open-source unified metadata management platform that provides a centralized way to discover, manage, and govern metadata across various data systems and storage engines. 

This repo provides an example of how to deploy a basic Gravitino setup with a Strimzi managed Kafka cluster. 
It then walks through the various metadata management operations, related to Kafka.

## Prerequisites

- Kubernetes cluster (e.g. Minikube)
- helm 
- kubectl 
- mc (MinIO client)
- psql (PostgreSQL client)
- jq (command-line JSON processor)

## Installation

This installation assumes you have a working Kubernetes cluster, with adequate resources (minimum 6 CPUS and 16GB of RAM) and have `kubectl` and `helm` installed and configured to access your cluster.

For example, you can use [Minikube](https://minikube.sigs.k8s.io/docs/start/) to create a local Kubernetes cluster for testing purposes:

```shell
 minikube start --cpus 8 --memory 28G --disk-size 50g
 ```

### Automated install

You can run the `install.sh` script, in the `setup` folder, to automatically install Gravitino, Strimzi Kafka and other dependencies. The `setup.sh` will create the necessary, topics, tables and filesets in the installed components and add the relevant entries to Gravitino.:

```shell
./setup/install.sh
./setup/setup.sh
```

Alternatively, you can follow the manual installation steps below.

## Using Gravitino

You can now use the operations described in the Gravitino Kafka Catalog [documentation](https://gravitino.apache.org/docs/1.0.0/manage-massaging-metadata-using-gravitino/) to manage the metadata associated with the Strimzi managed Kafka cluster and other components.

### Tagging Metadata Objects

In Gravitino, you can create [tags](https://gravitino.apache.org/docs/1.0.0/manage-tags-in-gravitino/) within a metalake, catalog or schema and then attach them to metadata objects.

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
