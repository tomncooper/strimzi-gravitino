package com.github.streams.gravitino.service;

import com.github.streams.gravitino.config.AppConfig;
import com.github.streams.gravitino.config.GravitinoConfig;
import org.apache.gravitino.Catalog;
import org.apache.gravitino.NameIdentifier;
import org.apache.gravitino.client.GravitinoClient;
import org.apache.gravitino.messaging.Topic;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

/**
 * Service for interacting with Gravitino metadata layer.
 * Queries messaging catalogs and validates topic existence.
 */
public class GravitinoService {
    private static final Logger logger = LoggerFactory.getLogger(GravitinoService.class);

    private final GravitinoConfig gravitinoConfig;
    private final AppConfig appConfig;
    private String kafkaBootstrapServers;

    public GravitinoService(GravitinoConfig gravitinoConfig, AppConfig appConfig) {
        this.gravitinoConfig = gravitinoConfig;
        this.appConfig = appConfig;
    }

    /**
     * Initialize Gravitino connection and retrieve Kafka bootstrap servers from catalog.
     */
    public void initialize() {
        logger.info("Initializing Gravitino service...");

        try {
            GravitinoClient client = gravitinoConfig.getClient();
            String catalogName = appConfig.getMessagingCatalog();

            logger.info("Loading messaging catalog: {}", catalogName);
            Catalog catalog = client.loadCatalog(catalogName);

            // Extract bootstrap servers from catalog properties
            Map<String, String> properties = catalog.properties();
            kafkaBootstrapServers = properties.get("bootstrap.servers");

            if (kafkaBootstrapServers == null || kafkaBootstrapServers.isEmpty()) {
                throw new RuntimeException("Kafka bootstrap.servers not found in catalog properties");
            }

            logger.info("Retrieved Kafka bootstrap servers from Gravitino: {}", kafkaBootstrapServers);

            // Verify topics exist
            verifyTopicsExist();

        } catch (Exception e) {
            logger.error("Failed to initialize Gravitino service", e);
            throw new RuntimeException("Failed to initialize Gravitino service", e);
        }
    }

    /**
     * Verify that configured topics exist in the Gravitino catalog.
     */
    private void verifyTopicsExist() {
        String clickstreamTopic = appConfig.getClickstreamTopic();
        String salesTopic = appConfig.getSalesTopic();

        logger.info("Verifying topics exist in Gravitino catalog...");
        logger.info("Checking clickstream topic: {}", clickstreamTopic);
        logger.info("Checking sales topic: {}", salesTopic);

        try {
            GravitinoClient client = gravitinoConfig.getClient();
            String catalogName = appConfig.getMessagingCatalog();

            // Load the catalog as messaging catalog
            Catalog catalog = client.loadCatalog(catalogName);

            // Verify clickstream topic
            boolean clickstreamExists = verifyTopic(catalog, clickstreamTopic);
            if (!clickstreamExists) {
                logger.warn("Clickstream topic '{}' not found in Gravitino catalog, " +
                           "but it may exist in Kafka", clickstreamTopic);
            }

            // Verify sales topic
            boolean salesExists = verifyTopic(catalog, salesTopic);
            if (!salesExists) {
                logger.warn("Sales topic '{}' not found in Gravitino catalog, " +
                           "but it may exist in Kafka", salesTopic);
            }

            logger.info("Topic verification completed");

        } catch (Exception e) {
            logger.error("Error verifying topics in Gravitino", e);
            throw new RuntimeException("Failed to verify topics in Gravitino", e);
        }
    }

    /**
     * Verify that a specific topic exists in the catalog.
     */
    private boolean verifyTopic(Catalog catalog, String topicName) {
        try {
            // For messaging catalogs, topics are typically in a "default" schema
            NameIdentifier topicId = NameIdentifier.of("default", topicName);

            // Try to load the topic
            Topic topic = catalog.asTopicCatalog().loadTopic(topicId);

            if (topic != null) {
                logger.info("Topic '{}' found in Gravitino catalog with {} partitions",
                           topicName, topic.properties().getOrDefault("partitions", "unknown"));
                return true;
            }
        } catch (Exception e) {
            logger.debug("Topic '{}' not found in Gravitino catalog: {}",
                        topicName, e.getMessage());
        }
        return false;
    }

    /**
     * Get Kafka bootstrap servers retrieved from Gravitino catalog.
     */
    public String getKafkaBootstrapServers() {
        if (kafkaBootstrapServers == null) {
            throw new IllegalStateException("Gravitino service not initialized. " +
                                          "Call initialize() first.");
        }
        return kafkaBootstrapServers;
    }
}
