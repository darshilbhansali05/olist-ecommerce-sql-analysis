-- ============================================================
-- PHASE 4: DATA CLEANING & VALIDATION
-- Project: Olist E-Commerce SQL Analysis
-- Purpose: Before doing any real analysis, check the data for
--          missing values, orphan records, duplicates, category
--          mismatches, and outliers/bad values. This phase is
--          about UNDERSTANDING data quality issues, not silently
--          fixing them.
-- ============================================================

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 4.1 MISSING DATES - OVERALL
-- Delivery-related dates (approved_at, carrier date, delivered
-- date, estimated date) drive the entire funnel analysis in
-- Phase 5, so we need to know upfront how many orders are
-- missing each milestone before we trust any delivery-time math.
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS missing_approved_at,
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS missing_carrier_date,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_delivered_date,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS missing_estimated_date
FROM orders;

-- ------------------------------------------------------------
-- 4.2 MISSING DATES - BROKEN DOWN BY ORDER STATUS
-- A missing delivered_date is EXPECTED for an order that's still
-- "shipped" or was "canceled" - that's not a data quality problem,
-- it's just reality. Grouping by order_status tells us whether
-- missing dates are concentrated in non-delivered statuses (fine)
-- or also show up under 'delivered' (a real problem - see 4.3).
-- ------------------------------------------------------------
SELECT
    order_status,
    COUNT(*) AS total,
    SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS missing_approved,
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS missing_carrier,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_delivered
FROM orders
GROUP BY order_status
ORDER BY total DESC;

-- ------------------------------------------------------------
-- 4.3 "DELIVERED" ORDERS WITH NO DELIVERY DATE (data quality flag)
-- These rows are a genuine inconsistency: Olist marked the order
-- as order_status = 'delivered' but never recorded the actual
-- delivery date. Worth eyeballing the raw rows to decide how to
-- treat them in Phase 5 (e.g. exclude from on-time/late %).
-- ------------------------------------------------------------
SELECT order_id, order_status, order_purchase_timestamp,
       order_approved_at, order_delivered_carrier_date,
       order_delivered_customer_date, order_estimated_delivery_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- ------------------------------------------------------------
-- 4.4 ORPHAN RECORDS
-- An "orphan" is a child-table row whose order_id doesn't exist
-- in the orders table at all. This can happen with real-world
-- exports (e.g. a row referencing a deleted/test order). A LEFT
-- JOIN + "parent IS NULL" is the standard pattern for finding these:
-- every child row is kept, and rows with no matching parent show
-- up as NULL on the parent's side.
-- ------------------------------------------------------------

-- Orphans in order_items (no matching order_id in orders)
SELECT COUNT(*) AS orphan_order_items
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Orphans in order_payments (no matching order_id in orders)
SELECT COUNT(*) AS orphan_order_payments
FROM order_payments op
LEFT JOIN orders o ON op.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Orphans in order_reviews (no matching order_id in orders)
SELECT COUNT(*) AS orphan_order_reviews
FROM order_reviews orv
LEFT JOIN orders o ON orv.order_id = o.order_id
WHERE o.order_id IS NULL;

-- ------------------------------------------------------------
-- 4.5 DUPLICATE ROWS
-- Since order_items has a composite PRIMARY KEY (order_id,
-- order_item_id), MySQL should already reject true duplicates at
-- insert time - this query is a double-check that nothing slipped
-- through (e.g. via a load that ran twice). HAVING COUNT(*) > 1
-- only keeps groups where the same key combination appears more
-- than once.
-- ------------------------------------------------------------
SELECT order_id, order_item_id, COUNT(*) AS cnt
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- Same check on orders: order_id is the primary key, so this
-- should always return zero rows. Confirms the table wasn't
-- accidentally loaded twice.
SELECT order_id, COUNT(*) AS cnt
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- ------------------------------------------------------------
-- 4.6 CATEGORY NAME CONSISTENCY
-- Analysis in later phases should always report categories in
-- English, so we need to confirm every product_category_name in
-- "products" has a matching row in the translation lookup table.
-- ------------------------------------------------------------

-- Category names that exist in "products" but have NO match in
-- the translation table (would show up as NULL/blank in reports
-- if not handled).
SELECT DISTINCT p.product_category_name
FROM products p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL;

-- How many products have a true NULL category (field was empty
-- in the CSV and loaded as NULL).
SELECT COUNT(*) AS products_missing_category
FROM products
WHERE product_category_name IS NULL;

-- How many products have an empty string '' as their category
-- (different from NULL - important because '' = NULL comparisons
-- would silently fail, so both cases need to be checked separately).
SELECT COUNT(*) AS empty_string_categories
FROM products
WHERE product_category_name = '';

-- Build the actual clean, English category label to use in
-- reporting: falls back to 'uncategorized' for blanks, falls back
-- to the original Portuguese name if no translation exists, and
-- otherwise uses the English translation.
SELECT
    p.product_id,
    CASE
        WHEN p.product_category_name = '' THEN 'uncategorized'
        WHEN t.product_category_name_english IS NULL THEN p.product_category_name
        ELSE t.product_category_name_english
    END AS category_english
FROM products p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name;

-- ------------------------------------------------------------
-- 4.7 OUTLIERS / BAD VALUES - PRICE & FREIGHT
-- price <= 0 or freight_value < 0 shouldn't exist in a real
-- e-commerce order; MIN/MAX also gives a quick sanity check for
-- absurdly large values that might be data entry errors.
-- ------------------------------------------------------------
SELECT
    SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END) AS bad_price,
    SUM(CASE WHEN freight_value < 0 THEN 1 ELSE 0 END) AS bad_freight,
    MIN(price) AS min_price,
    MAX(price) AS max_price
FROM order_items;

-- ------------------------------------------------------------
-- 4.8 OUTLIERS / BAD VALUES - PAYMENTS
-- payment_value <= 0 is suspicious (e.g. a fully-voucher-covered
-- order might legitimately show 0, but it's worth confirming why).
-- ------------------------------------------------------------
SELECT
    SUM(CASE WHEN payment_value <= 0 THEN 1 ELSE 0 END) AS bad_payment,
    MIN(payment_value) AS min_payment,
    MAX(payment_value) AS max_payment
FROM order_payments;

-- Look at the actual rows behind the "bad_payment" count above,
-- joined to orders so we can see the order_status alongside each
-- zero/negative payment - helps decide if these are legitimate
-- (e.g. canceled orders) or genuine data errors.
SELECT op.order_id, op.payment_type, op.payment_installments, op.payment_value, o.order_status
FROM order_payments op
JOIN orders o ON op.order_id = o.order_id
WHERE op.payment_value <= 0;

-- Spot-check a handful of specific order_ids found above in full
-- detail (all payment rows for these orders) - useful when an
-- order has multiple payment_sequential rows and you want to see
-- the full picture rather than just the flagged row.
SELECT order_id, payment_sequential, payment_type, payment_installments, payment_value
FROM order_payments
WHERE order_id IN (
    '45ed6e85398a87c253db47c2d9f48216',
    '6ccb433e00daae1283ccc956189c82ae',
    '8bcbe01d44d147f901cd3192671144db',
    'b23878b3e8eb4d25a158f57d96331b18',
    'fa65dad1b0e818e3ccc5cb0e39231352'
)
ORDER BY order_id, payment_sequential;

-- ============================================================
-- End of Phase 4.
-- Next: Phase 5 - delivery funnel analysis.
-- ============================================================
