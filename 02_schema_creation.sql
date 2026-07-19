-- ============================================================
-- PHASE 2: CREATE TABLE SCHEMA
-- Project: Olist E-Commerce SQL Analysis
-- Purpose: Define all 9 tables with correct data types, keys,
--          and utf8mb4 encoding (needed for Portuguese accented
--          characters in city/state names).
--
-- IMPORTANT: Table creation order matters. A foreign key can
-- only reference a table that already exists, so we always
-- create "parent" tables (referenced tables) BEFORE the "child"
-- tables that point to them. Order used below:
--   1. customers                (no dependencies)
--   2. sellers                  (no dependencies)
--   3. product_category_name_translation  (no dependencies)
--   4. products                 (depends on #3)
--   5. orders                   (depends on #1)
--   6. geolocation              (no formal FK - see note below)
--   7. order_items              (depends on #5, #4, #2)
--   8. order_payments           (depends on #5)
--   9. order_reviews            (depends on #5)
-- ============================================================

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 1. CUSTOMERS
-- One row per customer_id (Olist assigns a new customer_id per
-- order; customer_unique_id is the true person across orders).
-- ------------------------------------------------------------
CREATE TABLE customers (
    customer_id VARCHAR(32) PRIMARY KEY,
    customer_unique_id VARCHAR(32) NOT NULL,
    customer_zip_code_prefix INT,
    customer_city VARCHAR(100),
    customer_state VARCHAR(2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 2. SELLERS
-- One row per seller.
-- ------------------------------------------------------------
CREATE TABLE sellers (
    seller_id VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix INT,
    seller_city VARCHAR(100),
    seller_state VARCHAR(2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 3. PRODUCT CATEGORY NAME TRANSLATION
-- Lookup table: maps Portuguese category names -> English.
-- Created before "products" because products.product_category_name
-- has a foreign key pointing to this table.
-- ------------------------------------------------------------
CREATE TABLE product_category_name_translation (
    product_category_name VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 4. PRODUCTS
-- One row per product. product_name_lenght / product_description_lenght
-- are spelled this way (missing "g") because that's how Olist's
-- original CSV headers are spelled - kept as-is to match the source data.
-- ------------------------------------------------------------
CREATE TABLE products (
    product_id VARCHAR(32) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT,
    FOREIGN KEY (product_category_name)
        REFERENCES product_category_name_translation(product_category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 5. ORDERS
-- One row per order. This is the central "fact" table that
-- almost every analysis (delivery funnel, cohorts, AOV) joins to.
-- ------------------------------------------------------------
CREATE TABLE orders (
    order_id VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(32) NOT NULL,
    order_status VARCHAR(20),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 6. GEOLOCATION
-- No primary key / foreign key here on purpose: this dataset
-- has multiple lat/lng rows per zip_code_prefix (duplicates by
-- design), so it can't cleanly be a strict FK parent. It's used
-- for geographic joins on zip_code_prefix only.
-- ------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix INT,
    geolocation_lat DECIMAL(10,7),
    geolocation_lng DECIMAL(10,7),
    geolocation_city VARCHAR(100),
    geolocation_state VARCHAR(2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 7. ORDER ITEMS
-- One row per item within an order (an order can have multiple
-- items/products, hence the composite key order_id + order_item_id).
-- ------------------------------------------------------------
CREATE TABLE order_items (
    order_id VARCHAR(32) NOT NULL,
    order_item_id INT NOT NULL,
    product_id VARCHAR(32) NOT NULL,
    seller_id VARCHAR(32) NOT NULL,
    shipping_limit_date DATETIME,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (seller_id) REFERENCES sellers(seller_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 8. ORDER PAYMENTS
-- One row per payment transaction on an order (an order can be
-- split across multiple payment methods, hence payment_sequential).
-- ------------------------------------------------------------
CREATE TABLE order_payments (
    order_id VARCHAR(32) NOT NULL,
    payment_sequential INT NOT NULL,
    payment_type VARCHAR(20),
    payment_installments INT,
    payment_value DECIMAL(10,2),
    PRIMARY KEY (order_id, payment_sequential),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- 9. ORDER REVIEWS
-- One row per review. Composite key (review_id, order_id) because
-- the same review_id can occasionally repeat across orders in the
-- raw data.
-- ------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id VARCHAR(32) NOT NULL,
    order_id VARCHAR(32) NOT NULL,
    review_score INT,
    review_comment_title VARCHAR(255),
    review_comment_message TEXT,
    review_creation_date DATETIME,
    review_answer_timestamp DATETIME,
    PRIMARY KEY (review_id, order_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- Sanity check: confirm all 9 tables were created.
-- ------------------------------------------------------------
SHOW TABLES;

-- ============================================================
-- End of Phase 2.
-- Next: switch to Phase 3 to import the CSV data.
-- ============================================================
