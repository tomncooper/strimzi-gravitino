package com.github.streams.gravitino.model;

/**
 * Product inventory data model.
 * Maps CSV columns: id -> product_id, category -> category, price -> stock, quantity -> rating
 */
public class ProductInventory {
    private String productId;
    private String category;
    private int stock;
    private int rating;

    public ProductInventory() {
    }

    public ProductInventory(String productId, String category, int stock, int rating) {
        this.productId = productId;
        this.category = category;
        this.stock = stock;
        this.rating = rating;
    }

    public String getProductId() {
        return productId;
    }

    public void setProductId(String productId) {
        this.productId = productId;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public int getStock() {
        return stock;
    }

    public void setStock(int stock) {
        this.stock = stock;
    }

    public int getRating() {
        return rating;
    }

    public void setRating(int rating) {
        this.rating = rating;
    }

    @Override
    public String toString() {
        return "ProductInventory{" +
                "productId='" + productId + '\'' +
                ", category='" + category + '\'' +
                ", stock=" + stock +
                ", rating=" + rating +
                '}';
    }
}
