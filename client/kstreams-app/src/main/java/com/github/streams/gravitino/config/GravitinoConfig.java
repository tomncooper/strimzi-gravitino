package com.github.streams.gravitino.config;

import org.apache.gravitino.client.GravitinoClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Gravitino client configuration and initialization.
 */
public class GravitinoConfig {
    private static final Logger logger = LoggerFactory.getLogger(GravitinoConfig.class);

    private final GravitinoClient client;
    private final String metalakeName;

    public GravitinoConfig(AppConfig appConfig) {
        this.metalakeName = appConfig.getMetalakeName();
        String serverUri = appConfig.getGravitinoServerUri();

        logger.info("Initializing Gravitino client with server URI: {}, metalake: {}",
                    serverUri, metalakeName);

        try {
            this.client = GravitinoClient.builder(serverUri)
                    .withMetalake(metalakeName)
                    .build();

            logger.info("Successfully initialized Gravitino client");
        } catch (Exception e) {
            logger.error("Failed to initialize Gravitino client", e);
            throw new RuntimeException("Failed to initialize Gravitino client", e);
        }
    }

    public GravitinoClient getClient() {
        return client;
    }

    public String getMetalakeName() {
        return metalakeName;
    }

    public void close() {
        if (client != null) {
            try {
                client.close();
                logger.info("Gravitino client closed successfully");
            } catch (Exception e) {
                logger.warn("Error closing Gravitino client", e);
            }
        }
    }
}
