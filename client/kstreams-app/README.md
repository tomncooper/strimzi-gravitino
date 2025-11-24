# Product Recommendation Kafka Streams Application

A Kafka Streams application demonstrating integration with Apache Gravitino for metadata management. This application showcases how Gravitino can be used to:

- Query Kafka cluster metadata from Gravitino messaging catalogs
- Load product data from MinIO via Gravitino Virtual File System (GVFS)
- Verify topic existence through Gravitino
- Integrate with Apicurio Registry for Avro schema management
- Process streaming data from multiple Kafka topics

## Architecture

The application performs the following operations:

1. **Gravitino Metadata Query**: Retrieves Kafka bootstrap servers from Gravitino's messaging catalog
2. **Topic Verification**: Validates that clickstream and sales topics exist in the catalog
3. **Schema Registry Integration**: Fetches Avro schemas from Apicurio Registry for deserialization
4. **Product Data Loading**: Loads product inventory CSV from MinIO using GVFS with S3 compatibility
5. **Stream Processing**: Creates KTables for clickstream and sales data with Avro deserialization

## Prerequisites

- Java 17+
- Maven 3.9+
- Docker (for containerization)
- Kubernetes cluster with:
  - Gravitino deployed in `metadata` namespace
  - Kafka cluster (Strimzi) in `kafka` namespace
  - MinIO in `minio-tenant` namespace
  - Apicurio Registry in `registry` namespace
  - PostgreSQL in `postgres` namespace

## Project Structure

```
ProductRecommendation/
├── src/main/java/com/github/streams/gravitino/
│   ├── ProductRecommendationApp.java       # Main application
│   ├── config/
│   │   ├── AppConfig.java                  # Configuration management
│   │   └── GravitinoConfig.java            # Gravitino client setup
│   ├── model/
│   │   └── ProductInventory.java           # Product data model
│   ├── service/
│   │   ├── GravitinoService.java           # Gravitino metadata queries
│   │   ├── SchemaRegistryService.java      # Apicurio schema fetching
│   │   └── ProductDataLoader.java          # GVFS CSV loading
│   └── topology/
│       └── StreamsTopology.java            # Kafka Streams topology
├── kubernetes/
│   ├── namespace.yaml                      # Kubernetes namespace
│   ├── deployment.yaml                     # Application deployment
│   └── minio-secret.yaml                   # MinIO credentials template
├── Dockerfile                              # Multi-stage Docker build
└── pom.xml                                 # Maven configuration
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
kafka.clickstream.topic=clickStream
kafka.sales.topic=sales

# Apicurio Registry
apicurio.registry.url=http://apicurio-registry-service.registry.svc:8080/apis/registry/v2
```

### Environment Variables

The following environment variables can override application properties:

- `GRAVITINO_SERVER_URI`: Gravitino server URL
- `APICURIO_REGISTRY_URL`: Apicurio Registry URL
- `CLICKSTREAM_TOPIC`: Clickstream topic name
- `SALES_TOPIC`: Sales topic name
- `S3_ACCESS_KEY`: MinIO/S3 access key (from Kubernetes secret)
- `S3_SECRET_KEY`: MinIO/S3 secret key (from Kubernetes secret)

## Building the Application

### Build with Maven

```bash
cd ProductRecommendation
mvn clean package
```

The uber JAR will be created at: `target/product-recommendation-1.0.0.jar`

### Build Docker Image

```bash
docker build -t product-recommendation:1.0.0 .
```

For Kubernetes deployment, push to your registry:

```bash
docker tag product-recommendation:1.0.0 <your-registry>/product-recommendation:1.0.0
docker push <your-registry>/product-recommendation:1.0.0
```

Update the image reference in `kubernetes/deployment.yaml` accordingly.

## Running Locally

### Prerequisites for Local Execution

1. Port-forward required services:

```bash
# Gravitino
kubectl -n metadata port-forward svc/gravitino 8090:8090

# Apicurio Registry
kubectl -n registry port-forward svc/apicurio-registry-service 8080:8080

# Kafka (if accessing locally)
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

#### 1. Schema Not Found in Registry

**Symptoms**: Application logs show schema fetch errors

**Solution**: Verify Apicurio Registry has schemas:
```bash
kubectl -n registry port-forward svc/apicurio-registry-service 8080:8080
curl http://localhost:8080/apis/registry/v2/search/artifacts
```

Ensure data generator is running to create schemas:
```bash
kubectl -n data-generator get deployment recommendation-app-data
```

#### 2. Cannot Load Product CSV

**Symptoms**: GVFS errors or file not found

**Solution**: Verify MinIO bucket and file exist:
```bash
# Port-forward MinIO
kubectl -n minio-tenant port-forward svc/myminio-hl 9000:9000

# List files (requires mc client)
mc ls myminio/product-csvs/productInventory.csv --insecure
```

#### 3. Kafka Connection Failed

**Symptoms**: Cannot connect to Kafka cluster

**Solution**: Verify Gravitino catalog has correct bootstrap servers:
```bash
kubectl -n metadata port-forward svc/gravitino 8090:8090

curl -X GET -H "Accept: application/vnd.gravitino.v1+json" \
  http://localhost:8090/api/metalakes/demolake/catalogs/my_cluster_catalog
```

## Application Flow

1. **Initialization**
   - Loads configuration from application.properties
   - Initializes Gravitino client

2. **Metadata Query**
   - Queries `my_cluster_catalog` for Kafka bootstrap servers
   - Verifies `clickStream` and `sales` topics exist

3. **Schema Fetching**
   - Fetches Avro schemas from Apicurio Registry
   - Caches schemas for deserialization

4. **Product Data Loading**
   - Configures GVFS for MinIO/S3 access
   - Reads `productInventory.csv` from fileset catalog
   - Loads products into in-memory cache
   - Maps CSV columns: id→product_id, category→category, price→stock, quantity→rating

5. **Stream Processing**
   - Creates KTable for clickStream topic with Avro deserialization
   - Creates KTable for sales topic with Avro deserialization
   - Processes records with product enrichment capability

## Development

### Adding New Features

To extend this application:

1. **Add Stream Enrichment**: Modify `StreamsTopology.java` to join streams with product data
2. **Add Output Topics**: Configure producers to write enriched data
3. **Add More Filesets**: Use `ProductDataLoader` pattern for additional CSV files
4. **Custom Processing**: Implement transformers/processors in the topology

### Testing

```bash
# Run tests
mvn test

# Run with test coverage
mvn clean test jacoco:report
```

## Dependencies

Key dependencies:

- **Kafka Streams**: 3.9.0
- **Gravitino Client**: 1.0.1
- **Gravitino GVFS**: 1.0.1 (filesystem-hadoop3-runtime, aws-bundle)
- **Apicurio Registry Serdes**: 3.0.0
- **Apache Avro**: 1.11.3
- **Hadoop AWS**: 3.3.6

See `pom.xml` for complete dependency list.

## License

Apache License 2.0

## Contributing

Contributions welcome! Please ensure:

1. Code follows existing patterns
2. Add appropriate logging
3. Update documentation
4. Test changes locally and in Kubernetes

## Contact

For questions or issues, please open an issue in the repository.
