# Product Recommendation Kafka Streams Application

A Kafka Streams application demonstrating integration with Apache Gravitino for metadata management. This application showcases how Gravitino can be used to:

- Query Kafka cluster metadata from Gravitino messaging catalogs
- Load product data from S3-compatible storage (MinIO) via Gravitino Virtual File System (GVFS)
- Verify topic existence through Gravitino
- Integrate with Apicurio Registry for Avro schema management
- Process streaming data from multiple Kafka topics using Confluent wire format

## Architecture

The application performs the following operations:

1. **Gravitino Metadata Query**: Retrieves Kafka bootstrap servers from Gravitino's messaging catalog
2. **Topic Verification**: Validates that clickstream and sales topics exist in the catalog
3. **Product Data Loading**: Loads product inventory CSV from MinIO using GVFS with S3 compatibility
4. **Stream Processing**: Creates KTables for clickstream and sales data with Avro deserialization using Confluent wire format

## Prerequisites

- Java 17+
- Maven 3.9+
- Docker (for containerization)
- Kubernetes cluster with:
  - Gravitino deployed in `metadata` namespace
  - Kafka cluster (Strimzi) in `kafka` namespace
  - MinIO in `minio-tenant` namespace
  - Apicurio Registry in `registry` namespace
  - Data generator in `data-generator` namespace

## Project Structure

```
client/kstreams-app/
├── src/main/java/com/github/streams/gravitino/
│   ├── ProductRecommendationApp.java       # Main application
│   ├── config/
│   │   ├── AppConfig.java                  # Configuration management
│   │   └── GravitinoConfig.java            # Gravitino client setup
│   ├── model/
│   │   └── ProductInventory.java           # Product data model
│   ├── service/
│   │   ├── GravitinoService.java           # Gravitino metadata queries
│   │   └── ProductDataLoader.java          # GVFS CSV loading
│   └── topology/
│       └── StreamsTopology.java            # Kafka Streams topology
├── src/main/resources/
│   └── application.properties              # Application configuration
├── kubernetes/
│   ├── namespace.yaml                      # Kubernetes namespace
│   ├── deployment.yaml                     # Application deployment
│   └── minio-secret.yaml                   # MinIO credentials template
├── Dockerfile                              # Single-stage runtime Docker build
├── pom.xml                                 # Maven configuration
└── README.md                               # This file
```

## Configuration

### Application Properties

The application is configured via `src/main/resources/application.properties`:

```properties
# Gravitino Configuration
gravitino.server.uri=http://gravitino.metadata.svc.cluster.local:8090
gravitino.metalake=demolake
gravitino.messaging.catalog=my_cluster_catalog
gravitino.fileset.catalog=product_files
gravitino.fileset.schema=product_schema
gravitino.fileset.name=product_inventory_fileset

# Kafka Topics (configurable via environment variables)
kafka.clickstream.topic=flink.click.streams
kafka.sales.topic=flink.sales.records
kafka.application.id=product-recommendation-app
kafka.auto.offset.reset=earliest
kafka.commit.interval.ms=5000

# Apicurio Registry Configuration
apicurio.registry.url=http://apicurio-registry-service.registry.svc:8080/apis/registry/v2
apicurio.registry.find-latest=true

# Product CSV Configuration
product.csv.path=gvfs://fileset/product_files/product_schema/product_inventory_fileset/productInventory.csv

# GVFS Configuration for S3/MinIO
fs.AbstractFileSystem.gvfs.impl=org.apache.gravitino.filesystem.hadoop.Gvfs
fs.gvfs.impl=org.apache.gravitino.filesystem.hadoop.GravitinoVirtualFileSystem
fs.gravitino.server.uri=http://gravitino.metadata.svc.cluster.local:8090
fs.gravitino.client.metalake=demolake

# S3/MinIO Configuration
s3.endpoint=https://myminio-hl.minio-tenant.svc.cluster.local:9000
# S3_ACCESS_KEY and S3_SECRET_KEY provided as environment variables from Kubernetes secret
```

### Environment Variables

The following environment variables can override application properties:

- `GRAVITINO_SERVER_URI`: Gravitino server URL
- `APICURIO_REGISTRY_URL`: Apicurio Registry URL
- `S3_ACCESS_KEY`: MinIO/S3 access key (from Kubernetes secret)
- `S3_SECRET_KEY`: MinIO/S3 secret key (from Kubernetes secret)
- `JAVA_TOOL_OPTIONS`: JVM options (set by deployment for truststore)

### Wire Format Compatibility

The application uses **Confluent wire format** (`SerdeConfig.ENABLE_CONFLUENT_ID_HANDLER=true`) for Avro serialization/deserialization to match the data generator's schema encoding. This ensures compatibility with messages produced by the [StreamsHub data generator](https://github.com/streamshub/flink-sql-examples/tree/main/tutorials/data-generator).

## Building the Application

### Step 1: Build with Maven

```bash
cd client/kstreams-app
mvn clean package
```

The uber JAR will be created at: `target/product-recommendation-1.0.0.jar`

### Step 2: Build Docker Image

**For Minikube deployment:**

```bash
# Point Docker CLI to Minikube's Docker daemon
eval $(minikube -p minikube docker-env)

# Build the image
docker build -t localhost/product-recommendation:1.0.0 .
```

**For standard Kubernetes deployment:**

```bash
docker build -t product-recommendation:1.0.0 .
docker tag product-recommendation:1.0.0 <your-registry>/product-recommendation:1.0.0
docker push <your-registry>/product-recommendation:1.0.0
```

Update the image reference in `kubernetes/deployment.yaml` accordingly.

**Note:** The Dockerfile expects the JAR to be pre-built. Always run `mvn clean package` before building the Docker image.

## Running Locally

### Prerequisites for Local Execution

1. Port-forward required services:

```bash
# Gravitino
kubectl -n metadata port-forward svc/gravitino 8090:8090

# Apicurio Registry
kubectl -n registry port-forward svc/apicurio-registry-service 8080:8080

# Kafka
kubectl -n kafka port-forward svc/my-cluster-kafka-bootstrap 9092:9092

# MinIO
kubectl -n minio-tenant port-forward svc/myminio-hl 9000:9000
```

2. Export MinIO credentials:

```bash
export S3_ACCESS_KEY=$(kubectl -n metadata get secret gravitino-minio-credentials -o jsonpath='{.data.access-key}' | base64 -d)
export S3_SECRET_KEY=$(kubectl -n metadata get secret gravitino-minio-credentials -o jsonpath='{.data.secret-key}' | base64 -d)
```

3. Update `application.properties` for local access:

```properties
gravitino.server.uri=http://localhost:8090
apicurio.registry.url=http://localhost:8080/apis/registry/v2
s3.endpoint=https://localhost:9000
```

### Run the Application

```bash
java -jar target/product-recommendation-1.0.0.jar
```

## Deploying to Kubernetes

### Step 1: Create Namespace

```bash
kubectl apply -f kubernetes/namespace.yaml
```

### Step 2: Create MinIO Credentials Secret

Copy the existing MinIO credentials from the metadata namespace:

```bash
kubectl get secret gravitino-minio-credentials -n metadata -o json | \
  jq 'del(.metadata.namespace, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp)' | \
  jq '.metadata.name = "minio-credentials"' | \
  jq '.metadata.namespace = "product-recommendation"' | \
  kubectl apply -f -
```

### Step 3: Deploy Application

```bash
kubectl apply -f kubernetes/deployment.yaml
```

### Step 4: Verify Deployment

```bash
# Check deployment status
kubectl -n product-recommendation get deployments

# Check pod status
kubectl -n product-recommendation get pods

# View logs
kubectl -n product-recommendation logs -l app=product-recommendation -f
```

## Kubernetes Deployment Details

### SSL Certificate Handling

The deployment uses an **init container** to configure SSL certificates for MinIO HTTPS connectivity:

```yaml
initContainers:
  - name: setup-truststore
    command:
      - /bin/bash
      - -c
      - |
        # Copy default JVM truststore
        cp $JAVA_HOME/lib/security/cacerts /truststore/cacerts

        # Import Kubernetes CA certificate
        keytool -importcert -noprompt \
          -keystore /truststore/cacerts \
          -storepass changeit \
          -alias kubernetes-ca \
          -file /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

The main container uses the custom truststore via `JAVA_TOOL_OPTIONS`:

```yaml
env:
  - name: JAVA_TOOL_OPTIONS
    value: "-Djavax.net.ssl.trustStore=/truststore/cacerts -Djavax.net.ssl.trustStorePassword=changeit"
```

This allows the application to trust MinIO's self-signed certificate issued by the Kubernetes CA.

## Monitoring and Troubleshooting

### View Application Logs

```bash
kubectl -n product-recommendation logs -l app=product-recommendation -f
```

### Check Kafka Streams State

```bash
# Get pod name
POD=$(kubectl -n product-recommendation get pod -l app=product-recommendation -o jsonpath='{.items[0].metadata.name}')

# Check application is running
kubectl -n product-recommendation exec -it $POD -- ps aux | grep product-recommendation
```

### Common Issues

#### 1. Wire Format Mismatch (Schema Deserialization Error)

**Symptoms**:
```
java.lang.RuntimeException: io.apicurio.registry.rest.client.models.Error
  at io.apicurio.registry.resolver.ERCache.retry
```

**Cause**: Data generator uses Confluent wire format but deserializers expect Apicurio format

**Solution**: Verify `SerdeConfig.ENABLE_CONFLUENT_ID_HANDLER=true` is set in `StreamsTopology.java`:
```java
private Map<String, Object> createSerdeConfig() {
    Map<String, Object> config = new HashMap<>();
    config.put(SerdeConfig.REGISTRY_URL, appConfig.getApicurioRegistryUrl());
    config.put(SerdeConfig.FIND_LATEST_ARTIFACT, appConfig.getApicurioFindLatest());
    config.put(SerdeConfig.ENABLE_CONFLUENT_ID_HANDLER, true);  // Required!
    return config;
}
```

#### 2. Jackson Version Conflict

**Symptoms**:
```
java.lang.NoClassDefFoundError: com/fasterxml/jackson/core/exc/StreamConstraintsException
```

**Cause**: Apicurio Registry requires Jackson 2.15.0+ but transitive dependencies provide older versions

**Solution**: Use `<dependencyManagement>` in `pom.xml` to force Jackson 2.17.2:
```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-core</artifactId>
            <version>2.17.2</version>
        </dependency>
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
            <version>2.17.2</version>
        </dependency>
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-annotations</artifactId>
            <version>2.17.2</version>
        </dependency>
    </dependencies>
</dependencyManagement>
```

#### 3. SSL Certificate Error (MinIO Connection)

**Symptoms**: Application hangs when loading CSV or logs show SSL handshake errors

**Cause**: JVM doesn't trust MinIO's self-signed certificate

**Solution**: Verify init container is running and truststore is mounted:
```bash
kubectl -n product-recommendation describe pod <pod-name>
```

Ensure `JAVA_TOOL_OPTIONS` environment variable is set in deployment.

#### 4. Schema Not Found in Registry

**Symptoms**: Application logs show schema fetch errors

**Solution**: Verify Apicurio Registry has schemas:
```bash
kubectl -n registry port-forward svc/apicurio-registry-service 8080:8080
curl http://localhost:8080/apis/registry/v2/search/artifacts
```

Ensure data generator is running to create schemas:
```bash
kubectl -n data-generator get deployment recommendation-app-data
kubectl -n data-generator logs -l app=recommendation-app-data
```

#### 5. Cannot Load Product CSV

**Symptoms**: GVFS errors or file not found

**Solution**: Verify MinIO bucket and file exist:
```bash
# Port-forward MinIO
kubectl -n minio-tenant port-forward svc/myminio-hl 9000:9000

# List files (requires mc client)
mc alias set myminio https://localhost:9000 <access-key> <secret-key> --insecure
mc ls myminio/product-csvs/ --insecure
```

#### 6. Kafka Connection Failed

**Symptoms**: Cannot connect to Kafka cluster

**Solution**: Verify Gravitino catalog has correct bootstrap servers:
```bash
kubectl -n metadata port-forward svc/gravitino 8090:8090

curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  http://localhost:8090/api/metalakes/demolake/catalogs/my_cluster_catalog
```

## Application Flow

1. **Configuration Loading**
   - Loads configuration from `application.properties`
   - Overrides with environment variables
   - Initializes Gravitino client

2. **Metadata Query**
   - Queries `my_cluster_catalog` messaging catalog for Kafka bootstrap servers
   - Verifies `flink.click.streams` and `flink.sales.records` topics exist in Gravitino

3. **Product Data Loading**
   - Configures GVFS for MinIO/S3 access with HTTPS and SSL certificate validation
   - Reads `productInventory.csv` from fileset catalog via GVFS
   - Loads products into in-memory cache
   - Maps CSV columns: `id→product_id`, `category→category`, `price→stock`, `quantity→rating`

4. **Stream Processing**
   - Creates Kafka Streams configuration with Apicurio Registry and Confluent wire format
   - Creates KTable for `flink.click.streams` topic with Avro deserialization
   - Creates KTable for `flink.sales.records` topic with Avro deserialization
   - Processes records with product enrichment capability

## Development

### Adding New Features

To extend this application:

1. **Add Stream Enrichment**: Modify `StreamsTopology.java` to join streams with product data
2. **Add Output Topics**: Configure producers to write enriched data
3. **Add More Filesets**: Use `ProductDataLoader` pattern for additional CSV files
4. **Custom Processing**: Implement transformers/processors in the topology

### Quick Development Loop

```bash
# 1. Make code changes

# 2. Rebuild JAR
mvn clean package -q

# 3. Rebuild Docker image (for Minikube)
eval $(minikube -p minikube docker-env)
docker build -t localhost/product-recommendation:1.0.0 .

# 4. Restart deployment
kubectl -n product-recommendation rollout restart deployment/product-recommendation

# 5. Watch logs
kubectl -n product-recommendation logs -l app=product-recommendation -f
```

### Testing

```bash
# Run tests
mvn test

# Run with test coverage
mvn clean test jacoco:report
```

## Dependencies

Key dependencies (see `pom.xml` for complete list):

- **Kafka Streams**: 4.1.1
- **Kafka Clients**: 4.1.1
- **Gravitino Client**: 1.0.1
- **Gravitino GVFS**: 1.0.1 (filesystem-hadoop3-runtime, aws-bundle)
- **Apicurio Registry Serdes**: 3.0.0.M4
- **Apache Avro**: 1.12.1
- **Hadoop Common**: 3.4.2
- **Hadoop AWS**: 3.4.2
- **AWS SDK Bundle**: 1.12.793
- **OpenCSV**: 5.12.0
- **SLF4J**: 2.0.17
- **Logback**: 1.5.21
- **Jackson**: 2.17.2 (enforced via dependencyManagement)

## Architecture Notes

### Gravitino Virtual File System (GVFS)

The application uses GVFS to access MinIO storage through Gravitino's fileset catalog abstraction. This provides:

- **Unified metadata layer**: File locations managed through Gravitino catalogs
- **Credential management**: S3 credentials configured once in Gravitino
- **Path abstraction**: Use `gvfs://` URIs instead of direct S3 paths

### Apicurio Registry Integration

Schemas are automatically fetched from Apicurio Registry during deserialization:

- **Confluent wire format**: Compatible with StreamsHub data generator
- **Global ID resolution**: Schema IDs embedded in message headers
- **Automatic caching**: Schemas cached by Apicurio deserializers

### Product Data Model

CSV columns are mapped to the `ProductInventory` model:

| CSV Column | Model Field  | Type    | Description        |
|------------|--------------|---------|-------------------|
| id         | product_id   | String  | Unique product ID  |
| category   | category     | String  | Product category   |
| price      | stock        | int     | Stock quantity     |
| quantity   | rating       | int     | Product rating     |

## License

Apache License 2.0

## Contributing

Contributions welcome! Please ensure:

1. Code follows existing patterns
2. Add appropriate logging
3. Update documentation
4. Test changes locally and in Kubernetes
5. Verify compatibility with Gravitino 1.0.1 and Apicurio Registry

## Contact

For questions or issues, please open an issue in the repository.
