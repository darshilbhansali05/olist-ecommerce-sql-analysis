-- ============================================================
-- PHASE 5: DELIVERY FUNNEL ANALYSIS
-- Project: Olist E-Commerce SQL Analysis
-- Purpose: Measure how orders move through the delivery pipeline
--          (placed -> approved -> shipped to carrier -> delivered
--          to customer), where the drop-offs happen, and how
--          delivery performance varies by region/category/seller.
--
-- Note on approach: COUNT(column_name) in MySQL only counts
-- non-NULL values, so COUNT(order_approved_at) effectively counts
-- "how many orders have reached the approved stage" - that's the
-- trick used throughout this phase to build the funnel without
-- extra CASE statements.
-- ============================================================

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 5.1 RAW FUNNEL COUNTS
-- How many orders exist at each stage of the pipeline. Since
-- each date column is NULL until that stage happens, the count
-- naturally shrinks stage by stage.
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS total_orders,
    COUNT(order_approved_at) AS approved,
    COUNT(order_delivered_carrier_date) AS shipped,
    COUNT(order_delivered_customer_date) AS delivered
FROM orders;

-- ------------------------------------------------------------
-- 5.2 FUNNEL AS PERCENTAGES
-- Same idea as 5.1, but expressed as a % of total orders so the
-- drop-off at each stage is easier to read/present (e.g. in a
-- README chart or interview conversation).
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS total_orders,
    COUNT(order_approved_at) AS approved,
    ROUND(COUNT(order_approved_at) * 100.0 / COUNT(*), 2) AS pct_approved,
    COUNT(order_delivered_carrier_date) AS shipped,
    ROUND(COUNT(order_delivered_carrier_date) * 100.0 / COUNT(*), 2) AS pct_shipped,
    COUNT(order_delivered_customer_date) AS delivered,
    ROUND(COUNT(order_delivered_customer_date) * 100.0 / COUNT(*), 2) AS pct_delivered
FROM orders;

-- ------------------------------------------------------------
-- 5.3 ORDER STATUS BREAKDOWN
-- Shows the full spread of order_status values (delivered,
-- shipped, canceled, unavailable, etc.) as a % of all orders -
-- useful context for why the funnel in 5.1/5.2 doesn't reach 100%
-- delivered (some orders are legitimately still in transit,
-- canceled, or otherwise never reached the customer).
-- ------------------------------------------------------------
SELECT
    order_status,
    COUNT(*) AS num_orders,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders), 2) AS pct_of_total
FROM orders
GROUP BY order_status
ORDER BY num_orders DESC;

-- ------------------------------------------------------------
-- 5.4 ON-TIME VS LATE DELIVERY %
-- Compares the actual delivery date against Olist's own estimated
-- delivery date. Restricted to order_status = 'delivered' only,
-- since an order that was never delivered has no actual date to
-- compare against.
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'On Time'
        ELSE 'Late'
    END AS delivery_status,
    COUNT(*) AS num_orders,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM orders WHERE order_status = 'delivered'), 2) AS pct_of_delivered
FROM orders
WHERE order_status = 'delivered'
GROUP BY delivery_status;

-- ------------------------------------------------------------
-- 5.5 HOW LATE ARE LATE ORDERS?
-- For orders that missed their estimate, DATEDIFF gives the gap
-- in days between actual and estimated delivery. Average shows the
-- typical lateness; MAX shows the single worst case (useful for
-- spotting extreme outliers worth investigating separately).
-- ------------------------------------------------------------
SELECT
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date)), 1) AS avg_days_late,
    MAX(DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date)) AS worst_case_days_late
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date > order_estimated_delivery_date;

-- ------------------------------------------------------------
-- 5.6 DELIVERY PERFORMANCE BY CUSTOMER STATE
-- Joins orders to customers to see which Brazilian states have
-- the slowest average delivery time (purchase -> delivered) and
-- the highest % of late deliveries. Useful for spotting regional
-- logistics problems (e.g. remote states usually perform worse).
-- ------------------------------------------------------------
SELECT
    c.customer_state,
    COUNT(*) AS total_delivered_orders,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_late
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY pct_late DESC;

-- ------------------------------------------------------------
-- 5.7 DELIVERY PERFORMANCE BY PRODUCT CATEGORY
-- Chains through order_items -> products -> the category
-- translation table to report categories in English. HAVING
-- COUNT(*) >= 30 filters out tiny categories where one or two
-- slow orders would distort the % late (a form of "sample size"
-- reasoning worth mentioning in interviews).
-- ------------------------------------------------------------
SELECT
    pt.product_category_name_english AS category,
    COUNT(*) AS total_delivered_items,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_late
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_name_translation pt ON p.product_category_name = pt.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY pt.product_category_name_english
HAVING COUNT(*) >= 30
ORDER BY pct_late DESC
LIMIT 10;

-- ------------------------------------------------------------
-- 5.8 WORST-PERFORMING SELLERS
-- Same logic as 5.7 but grouped by seller instead of category,
-- with total_revenue added so low-performing sellers can also be
-- weighed against how much revenue they're responsible for.
-- HAVING COUNT(*) >= 50 applies the same sample-size filter.
-- ------------------------------------------------------------
SELECT
    oi.seller_id,
    COUNT(*) AS total_delivered_items,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_late
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY oi.seller_id
HAVING COUNT(*) >= 50
ORDER BY pct_late DESC
LIMIT 10;

-- ============================================================
-- End of Phase 5.
-- Next: Phase 6 - cohort and retention analysis.
-- ============================================================
