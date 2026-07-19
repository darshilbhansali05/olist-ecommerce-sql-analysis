-- ============================================================
-- PHASE 3: IMPORT CSV DATA
-- Project: Olist E-Commerce SQL Analysis
-- Purpose: Bulk-load all 9 CSVs using LOAD DATA LOCAL INFILE
--          (much faster and more reliable on 100k+ row files
--          than the Workbench Table Data Import Wizard).
--
-- Import order follows the same parent-before-child logic as
-- Phase 2's table creation, since foreign keys must be able to
-- resolve against rows that already exist in the parent table.
--
-- After every import, a SELECT COUNT(*) is run to confirm the
-- row count matches what Kaggle documents for that file - this
-- catches silently dropped/malformed rows early.
-- ============================================================

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 1. CUSTOMERS (no dependencies - safe to load first)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_customers_dataset.csv'
INTO TABLE customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM customers;  -- expect: 99441 rows (per Kaggle)

-- ------------------------------------------------------------
-- 2. SELLERS (no dependencies)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM sellers;  -- expect: 3095 rows

-- ------------------------------------------------------------
-- 3. PRODUCT CATEGORY NAME TRANSLATION (lookup table, load
--    before "products" since products has an FK pointing here)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM product_category_name_translation;  -- expect: 71 rows

-- ------------------------------------------------------------
-- 4. PRODUCTS
-- Safety reset in case this script is re-run: clears any rows
-- from a previous partial import so we don't get duplicate-key
-- errors or doubled row counts.
-- ------------------------------------------------------------
DELETE FROM products WHERE product_id <> '';

-- Foreign key checks are temporarily disabled for this one load
-- because the raw CSV can contain a handful of product_category_name
-- values that are blank/NULL or don't exist in the translation
-- table yet. Turning FK checks off lets those rows load instead
-- of failing the whole batch; we re-enable checks immediately after.
SET FOREIGN_KEY_CHECKS = 0;

-- Numeric columns are loaded into @-prefixed user variables first,
-- then written to the real columns via NULLIF(..., ''). This is
-- because empty CSV fields ('') would otherwise be inserted as 0
-- instead of NULL, which would quietly corrupt averages/analysis
-- later (e.g. product_weight_g = 0 looks like a real weight).
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, product_category_name, @name_len, @desc_len, @photos_qty, @weight, @length, @height, @width)
SET
  product_name_lenght        = NULLIF(@name_len, ''),
  product_description_lenght = NULLIF(@desc_len, ''),
  product_photos_qty         = NULLIF(@photos_qty, ''),
  product_weight_g           = NULLIF(@weight, ''),
  product_length_cm          = NULLIF(@length, ''),
  product_height_cm          = NULLIF(@height, ''),
  product_width_cm           = NULLIF(@width, '');

SET FOREIGN_KEY_CHECKS = 1;  -- always re-enable right after - don't leave this off

SELECT COUNT(*) FROM products;  -- expect: 32951 rows

-- ------------------------------------------------------------
-- 5. GEOLOCATION (no FK, loaded independently)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_geolocation_dataset.csv'
INTO TABLE geolocation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM geolocation;  -- expect: 1000163 rows

-- ------------------------------------------------------------
-- 6. ORDERS (depends on customers - must load after customers)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM orders;  -- expect: 99441 rows

-- ------------------------------------------------------------
-- 6a. CLEAN UP "ZERO DATES" IN ORDERS
-- MySQL's DATETIME columns can end up with the placeholder value
-- '0000-00-00 00:00:00' instead of a real NULL when a date is
-- missing (this happens for orders that were never delivered,
-- approved, etc.). We convert those placeholders to true NULLs so
-- that date math (e.g. delivery time calculations) doesn't silently
-- break or produce nonsense results in later phases.
-- ------------------------------------------------------------

-- Check how many zero-dates exist before cleaning
SELECT COUNT(*) AS zero_date_delivered
FROM orders
WHERE CAST(order_delivered_customer_date AS CHAR) = '0000-00-00 00:00:00';

UPDATE orders
SET order_delivered_customer_date = NULL
WHERE CAST(order_delivered_customer_date AS CHAR) = '0000-00-00 00:00:00'
  AND order_id <> '';

UPDATE orders
SET order_delivered_carrier_date = NULL
WHERE CAST(order_delivered_carrier_date AS CHAR) = '0000-00-00 00:00:00'
  AND order_id <> '';

UPDATE orders
SET order_approved_at = NULL
WHERE CAST(order_approved_at AS CHAR) = '0000-00-00 00:00:00'
  AND order_id <> '';

-- Verify the cleanup worked: all three counts below should be 0
SELECT
  SUM(CASE WHEN CAST(order_delivered_customer_date AS CHAR) = '0000-00-00 00:00:00' THEN 1 ELSE 0 END) AS still_zero_customer,
  SUM(CASE WHEN CAST(order_delivered_carrier_date AS CHAR)  = '0000-00-00 00:00:00' THEN 1 ELSE 0 END) AS still_zero_carrier,
  SUM(CASE WHEN CAST(order_approved_at AS CHAR)             = '0000-00-00 00:00:00' THEN 1 ELSE 0 END) AS still_zero_approved
FROM orders;

-- ------------------------------------------------------------
-- 7. ORDER ITEMS (depends on orders, products, sellers)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM order_items;  -- expect: 112650 rows

-- ------------------------------------------------------------
-- 8. ORDER PAYMENTS (depends on orders)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_order_payments_dataset.csv'
INTO TABLE order_payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM order_payments;  -- expect: 103886 rows

-- ------------------------------------------------------------
-- 9. ORDER REVIEWS (depends on orders)
-- ------------------------------------------------------------
LOAD DATA LOCAL INFILE '/Users/darshilbhansali/Downloads/Projects/Olist_project/CSV files/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) FROM order_reviews;  -- expect: 99224 rows

-- ============================================================
-- End of Phase 3.
-- All 9 tables are now populated. Next: Phase 4 - data cleaning
-- and validation (nulls, orphans, duplicates, outliers).
-- ============================================================
