package com.github.streams.gravitino.config;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

/**
 * Application configuration loader.
 * Loads properties from application.properties and environment variables.
 */
public class AppConfig {
    private final Properties properties;

    public AppConfig() {
        this.properties = new Properties();
        loadProperties();
        overrideWithEnvVars();
    }

    private void loadProperties() {
        try (InputStream input = getClass().getClassLoader()
                .getResourceAsStream("application.properties")) {
            if (input == null) {
                throw new RuntimeException("Unable to find application.properties");
            }
            properties.load(input);
        } catch (IOException ex) {
            throw new RuntimeException("Error loading application.properties", ex);
        }
    }

    private void overrideWithEnvVars() {
        // Override with environment variables if present
        String gravitinoUri = System.getenv("GRAVITINO_SERVER_URI");
        if (gravitinoUri != null) {
            properties.setProperty("gravitino.server.uri", gravitinoUri);
        }

        String apicurioUrl = System.getenv("APICURIO_REGISTRY_URL");
        if (apicurioUrl != null) {
            properties.setProperty("apicurio.registry.url", apicurioUrl);
        }

        String s3AccessKey = System.getenv("S3_ACCESS_KEY");
        if (s3AccessKey != null) {
            properties.setProperty("s3-access-key-id", s3AccessKey);
        }

        String s3SecretKey = System.getenv("S3_SECRET_KEY");
        if (s3SecretKey != null) {
            properties.setProperty("s3-secret-access-key", s3SecretKey);
        }

        String clickstreamTopic = System.getenv("CLICKSTREAM_TOPIC");
        if (clickstreamTopic != null) {
            properties.setProperty("kafka.clickstream.topic", clickstreamTopic);
        }

        String salesTopic = System.getenv("SALES_TOPIC");
        if (salesTopic != null) {
            properties.setProperty("kafka.sales.topic", salesTopic);
        }
    }

    public String getProperty(String key) {
        return properties.getProperty(key);
    }

    public String getProperty(String key, String defaultValue) {
        return properties.getProperty(key, defaultValue);
    }

    public Properties getProperties() {
        return properties;
    }

    // Gravitino configuration
    public String getGravitinoServerUri() {
        return getProperty("gravitino.server.uri");
    }

    public String getMetalakeName() {
        return getProperty("gravitino.metalake");
    }

    public String getMessagingCatalog() {
        return getProperty("gravitino.messaging.catalog");
    }

    public String getFilesetCatalog() {
        return getProperty("gravitino.fileset.catalog");
    }

    public String getFilesetSchema() {
        return getProperty("gravitino.fileset.schema");
    }

    public String getFilesetName() {
        return getProperty("gravitino.fileset.name");
    }

    // Kafka configuration
    public String getClickstreamTopic() {
        return getProperty("kafka.clickstream.topic");
    }

    public String getSalesTopic() {
        return getProperty("kafka.sales.topic");
    }

    public String getKafkaApplicationId() {
        return getProperty("kafka.application.id");
    }

    public String getAutoOffsetReset() {
        return getProperty("kafka.auto.offset.reset", "earliest");
    }

    // Apicurio Registry configuration
    public String getApicurioRegistryUrl() {
        return getProperty("apicurio.registry.url");
    }

    public boolean getApicurioFindLatest() {
        return Boolean.parseBoolean(getProperty("apicurio.registry.find-latest", "true"));
    }

    // Product CSV configuration
    public String getProductCsvPath() {
        return getProperty("product.csv.path");
    }

    // S3 configuration
    public String getS3Endpoint() {
        return getProperty("s3.endpoint");
    }

    public String getS3AccessKey() {
        return getProperty("s3-access-key-id");
    }

    public String getS3SecretKey() {
        return getProperty("s3-secret-access-key");
    }
}
