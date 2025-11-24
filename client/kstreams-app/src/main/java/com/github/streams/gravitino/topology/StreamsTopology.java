package com.github.streams.gravitino.topology;

import com.github.streams.gravitino.config.AppConfig;
import com.github.streams.gravitino.service.ProductDataLoader;
import io.apicurio.registry.serde.SerdeConfig;
import io.apicurio.registry.serde.avro.AvroKafkaDeserializer;
import io.apicurio.registry.serde.avro.AvroKafkaSerializer;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KTable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

/**
 * Kafka Streams topology for product recommendation application.
 * Creates KTables from clickStream and sales topics using Apicurio Avro deserializers.
 */
public class StreamsTopology {
    private static final Logger logger = LoggerFactory.getLogger(StreamsTopology.class);

    private final AppConfig appConfig;
    private final ProductDataLoader productDataLoader;
    private final String kafkaBootstrapServers;

    public StreamsTopology(AppConfig appConfig, ProductDataLoader productDataLoader, String kafkaBootstrapServers) {
        this.appConfig = appConfig;
        this.productDataLoader = productDataLoader;
        this.kafkaBootstrapServers = kafkaBootstrapServers;
    }

    /**
     * Create Kafka Streams configuration properties.
     */
    public Properties createStreamsConfig() {
        Properties props = new Properties();

        // Basic Kafka Streams configuration
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, appConfig.getKafkaApplicationId());
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, kafkaBootstrapServers);

        // Default Serdes
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.ByteArray().getClass());

        // Apicurio Registry configuration for deserializers
        props.put(SerdeConfig.REGISTRY_URL, appConfig.getApicurioRegistryUrl());
        props.put(SerdeConfig.FIND_LATEST_ARTIFACT, appConfig.getApicurioFindLatest());

        // Auto offset reset
        props.put(StreamsConfig.consumerPrefix("auto.offset.reset"), appConfig.getAutoOffsetReset());

        // Commit interval
        props.put(StreamsConfig.COMMIT_INTERVAL_MS_CONFIG,
                appConfig.getProperty("kafka.commit.interval.ms", "5000"));

        // Processing guarantee
        props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.EXACTLY_ONCE_V2);

        logger.info("Kafka Streams configuration created with bootstrap servers: {}", kafkaBootstrapServers);
        logger.info("Apicurio Registry URL: {}", appConfig.getApicurioRegistryUrl());

        return props;
    }

    /**
     * Build the Kafka Streams topology.
     */
    public Topology buildTopology() {
        logger.info("Building Kafka Streams topology...");

        StreamsBuilder builder = new StreamsBuilder();

        // Create Apicurio Avro Serde configuration
        Map<String, Object> serdeConfig = createSerdeConfig();

        // Create KTables for clickstream and sales topics
        KTable<String, GenericRecord> clickStreamTable = createClickStreamTable(builder, serdeConfig);
        KTable<String, GenericRecord> salesTable = createSalesTable(builder, serdeConfig);

        // Log the table contents for demonstration
        clickStreamTable.toStream().foreach((key, value) -> {
            logger.debug("ClickStream record - Key: {}, Value: {}", key, value);
            // Here you could enrich with product data if needed
            // ProductInventory product = productDataLoader.getProduct(someProductId);
        });

        salesTable.toStream().foreach((key, value) -> {
            logger.debug("Sales record - Key: {}, Value: {}", key, value);
            // Here you could enrich with product data if needed
        });

        Topology topology = builder.build();
        logger.info("Kafka Streams topology built successfully");
        logger.info("Topology description:\n{}", topology.describe());

        return topology;
    }

    /**
     * Create Serde configuration for Apicurio Registry.
     */
    private Map<String, Object> createSerdeConfig() {
        Map<String, Object> config = new HashMap<>();
        config.put(SerdeConfig.REGISTRY_URL, appConfig.getApicurioRegistryUrl());
        config.put(SerdeConfig.FIND_LATEST_ARTIFACT, appConfig.getApicurioFindLatest());
        // Enable Confluent ID handler to match data generator wire format
        config.put(SerdeConfig.ENABLE_CONFLUENT_ID_HANDLER, true);
        return config;
    }

    /**
     * Create KTable for clickstream topic using Apicurio Avro deserializer.
     */
    private KTable<String, GenericRecord> createClickStreamTable(StreamsBuilder builder,
                                                                  Map<String, Object> serdeConfig) {
        String topicName = appConfig.getClickstreamTopic();
        logger.info("Creating KTable for clickstream topic: {}", topicName);

        // Create Avro Serde with Apicurio Registry
        AvroKafkaDeserializer<GenericRecord> deserializer = new AvroKafkaDeserializer<>();
        deserializer.configure(serdeConfig, false);

        // Create consumer configuration with Apicurio Avro deserializer
        Consumed<String, GenericRecord> consumed = Consumed.with(
                Serdes.String(),
                Serdes.serdeFrom(
                        new AvroKafkaSerializer<>(),
                        deserializer
                )
        );

        KTable<String, GenericRecord> table = builder.table(topicName, consumed);
        logger.info("KTable created for topic: {}", topicName);

        return table;
    }

    /**
     * Create KTable for sales topic using Apicurio Avro deserializer.
     */
    private KTable<String, GenericRecord> createSalesTable(StreamsBuilder builder,
                                                            Map<String, Object> serdeConfig) {
        String topicName = appConfig.getSalesTopic();
        logger.info("Creating KTable for sales topic: {}", topicName);

        // Create Avro Serde with Apicurio Registry
        AvroKafkaDeserializer<GenericRecord> deserializer = new AvroKafkaDeserializer<>();
        deserializer.configure(serdeConfig, false);

        // Create consumed configuration with Apicurio Avro deserializer
        Consumed<String, GenericRecord> consumed = Consumed.with(
                Serdes.String(),
                Serdes.serdeFrom(
                        new AvroKafkaSerializer<>(),
                        deserializer
                )
        );

        KTable<String, GenericRecord> table = builder.table(topicName, consumed);
        logger.info("KTable created for topic: {}", topicName);

        return table;
    }
}
