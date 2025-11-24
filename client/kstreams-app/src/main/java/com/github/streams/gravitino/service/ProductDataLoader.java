package com.github.streams.gravitino.service;

import com.github.streams.gravitino.config.AppConfig;
import com.github.streams.gravitino.model.ProductInventory;
import com.opencsv.CSVReader;
import com.opencsv.exceptions.CsvException;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FSDataInputStream;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Loads product inventory data from CSV file using Gravitino Virtual File System (GVFS).
 * The CSV is stored in MinIO and accessed via GVFS fileset catalog.
 */
public class ProductDataLoader {
    private static final Logger logger = LoggerFactory.getLogger(ProductDataLoader.class);

    private final AppConfig appConfig;
    private final Map<String, ProductInventory> productCache;

    public ProductDataLoader(AppConfig appConfig) {
        this.appConfig = appConfig;
        this.productCache = new HashMap<>();
    }

    /**
     * Initialize GVFS configuration and load product data.
     */
    public void initialize() {
        logger.info("Initializing Product Data Loader with GVFS...");

        Configuration hadoopConf = createGVFSConfiguration();
        loadProductData(hadoopConf);

        logger.info("Product Data Loader initialized with {} products", productCache.size());
    }

    /**
     * Create Hadoop configuration for GVFS with S3/MinIO support.
     */
    private Configuration createGVFSConfiguration() {
        Configuration conf = new Configuration();

        // GVFS configuration
        conf.set("fs.AbstractFileSystem.gvfs.impl",
                appConfig.getProperty("fs.AbstractFileSystem.gvfs.impl"));
        conf.set("fs.gvfs.impl",
                appConfig.getProperty("fs.gvfs.impl"));
        conf.set("fs.gravitino.server.uri",
                appConfig.getProperty("fs.gravitino.server.uri"));
        conf.set("fs.gravitino.client.metalake",
                appConfig.getProperty("fs.gravitino.client.metalake"));

        // S3/MinIO configuration for GVFS
        String s3AccessKey = appConfig.getS3AccessKey();
        String s3SecretKey = appConfig.getS3SecretKey();
        String s3Endpoint = appConfig.getS3Endpoint();

        if (s3AccessKey != null && !s3AccessKey.isEmpty()) {
            conf.set("s3-access-key-id", s3AccessKey);
            logger.debug("S3 access key configured");
        }

        if (s3SecretKey != null && !s3SecretKey.isEmpty()) {
            conf.set("s3-secret-access-key", s3SecretKey);
            logger.debug("S3 secret key configured");
        }

        if (s3Endpoint != null && !s3Endpoint.isEmpty()) {
            conf.set("s3-endpoint", s3Endpoint);
            logger.debug("S3 endpoint configured: {}", s3Endpoint);
        }

        // Enable path-style access for MinIO compatibility
        conf.set("fs.s3a.path.style.access", "true");
        logger.debug("S3A path-style access enabled");

        logger.info("GVFS configuration created for MinIO access");
        return conf;
    }

    /**
     * Load product data from CSV file via GVFS.
     */
    private void loadProductData(Configuration hadoopConf) {
        String csvPath = appConfig.getProductCsvPath();
        logger.info("Loading product data from GVFS path: {}", csvPath);

        try {
            Path gvfsPath = new Path(csvPath);
            FileSystem fs = gvfsPath.getFileSystem(hadoopConf);

            logger.debug("Successfully connected to GVFS FileSystem");

            // Read CSV file
            try (FSDataInputStream inputStream = fs.open(gvfsPath);
                 BufferedReader bufferedReader = new BufferedReader(new InputStreamReader(inputStream));
                 CSVReader csvReader = new CSVReader(bufferedReader)) {

                List<String[]> rows = csvReader.readAll();
                logger.info("Read {} rows from CSV file", rows.size());

                // Parse CSV rows and populate product cache
                // CSV columns: id, category, price, quantity
                // Map to: product_id, category, stock, rating
                int rowCount = 0;
                for (String[] row : rows) {
                    if (row.length < 4) {
                        logger.warn("Skipping invalid row with {} columns: {}", row.length, String.join(",", row));
                        continue;
                    }

                    try {
                        String productId = row[0].trim();
                        String category = row[1].trim();
                        int stock = Integer.parseInt(row[2].trim());
                        int rating = Integer.parseInt(row[3].trim());

                        ProductInventory product = new ProductInventory(productId, category, stock, rating);
                        productCache.put(productId, product);
                        rowCount++;

                        if (rowCount <= 5) {
                            logger.debug("Loaded product: {}", product);
                        }
                    } catch (NumberFormatException e) {
                        logger.warn("Skipping row with invalid numeric values: {}", String.join(",", row));
                    }
                }

                logger.info("Successfully loaded {} products into memory", productCache.size());

            } catch (CsvException e) {
                logger.error("Error parsing CSV file", e);
                throw new RuntimeException("Failed to parse product CSV file", e);
            }

        } catch (IOException e) {
            logger.error("Error loading product data from GVFS", e);
            throw new RuntimeException("Failed to load product data from GVFS", e);
        }
    }

    /**
     * Get product by ID from the in-memory cache.
     */
    public ProductInventory getProduct(String productId) {
        return productCache.get(productId);
    }

    /**
     * Get all products.
     */
    public Map<String, ProductInventory> getAllProducts() {
        return new HashMap<>(productCache);
    }

    /**
     * Check if product exists.
     */
    public boolean hasProduct(String productId) {
        return productCache.containsKey(productId);
    }

    /**
     * Get count of loaded products.
     */
    public int getProductCount() {
        return productCache.size();
    }
}
