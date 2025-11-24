package com.github.streams.gravitino;

import com.github.streams.gravitino.config.AppConfig;
import com.github.streams.gravitino.config.GravitinoConfig;
import com.github.streams.gravitino.service.GravitinoService;
import com.github.streams.gravitino.service.ProductDataLoader;
import com.github.streams.gravitino.topology.StreamsTopology;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.Topology;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Properties;
import java.util.concurrent.CountDownLatch;

/**
 * Product Recommendation Kafka Streams Application.
 *
 * This application demonstrates integration with Apache Gravitino for metadata management:
 * 1. Queries Gravitino for Kafka bootstrap servers and topic metadata
 * 2. Fetches Avro schemas from Apicurio Registry
 * 3. Loads product data from MinIO via Gravitino Virtual File System (GVFS)
 * 4. Creates Kafka Streams topology with KTables using Apicurio Avro deserializers
 */
public class ProductRecommendationApp {
    private static final Logger logger = LoggerFactory.getLogger(ProductRecommendationApp.class);

    public static void main(String[] args) {
        logger.info("Starting Product Recommendation Kafka Streams Application...");

        ProductRecommendationApp app = new ProductRecommendationApp();
        app.run();
    }

    public void run() {
        // Step 1: Load configuration
        logger.info("Loading application configuration...");
        AppConfig appConfig = new AppConfig();
        logger.info("Configuration loaded successfully");

        // Step 2: Initialize Gravitino client
        logger.info("Initializing Gravitino client...");
        GravitinoConfig gravitinoConfig = new GravitinoConfig(appConfig);
        logger.info("Gravitino client initialized");

        // Step 3: Query Gravitino for Kafka metadata
        logger.info("Querying Gravitino for Kafka catalog and topic metadata...");
        GravitinoService gravitinoService = new GravitinoService(gravitinoConfig, appConfig);
        gravitinoService.initialize();
        String kafkaBootstrapServers = gravitinoService.getKafkaBootstrapServers();
        logger.info("Retrieved Kafka bootstrap servers: {}", kafkaBootstrapServers);

        // Step 4: Load product data from MinIO via GVFS
        logger.info("Loading product data from MinIO via Gravitino Virtual File System...");
        ProductDataLoader productDataLoader = new ProductDataLoader(appConfig);
        productDataLoader.initialize();
        logger.info("Product data loaded: {} products", productDataLoader.getProductCount());

        // Step 5: Build Kafka Streams topology
        logger.info("Building Kafka Streams topology...");
        StreamsTopology streamsTopology = new StreamsTopology(appConfig, productDataLoader, kafkaBootstrapServers);
        Properties streamsConfig = streamsTopology.createStreamsConfig();
        Topology topology = streamsTopology.buildTopology();
        logger.info("Kafka Streams topology built");

        // Step 6: Create and start Kafka Streams
        logger.info("Starting Kafka Streams application...");
        final KafkaStreams streams = new KafkaStreams(topology, streamsConfig);
        final CountDownLatch latch = new CountDownLatch(1);

        // Add shutdown hook
        Runtime.getRuntime().addShutdownHook(new Thread("streams-shutdown-hook") {
            @Override
            public void run() {
                logger.info("Shutdown signal received, stopping Kafka Streams...");
                streams.close();
                gravitinoConfig.close();
                latch.countDown();
                logger.info("Application stopped gracefully");
            }
        });

        try {
            // Clean up local state from previous runs (useful for development)
            streams.cleanUp();

            // Start the streams application
            streams.start();
            logger.info("Kafka Streams application started successfully");
            logger.info("Application is now processing data from topics: {}, {}",
                       appConfig.getClickstreamTopic(), appConfig.getSalesTopic());

            // Wait for shutdown
            latch.await();
        } catch (Throwable e) {
            logger.error("Fatal error in Kafka Streams application", e);
            System.exit(1);
        }
    }
}
