-- ============================================================
-- PHASE 6: COHORT AND RETENTION ANALYSIS
-- Project: Olist E-Commerce SQL Analysis
-- Purpose: Group customers by the month of their FIRST purchase
--          (their "cohort"), then track what % of each cohort
--          keeps buying in later months. This reveals whether
--          customer retention is improving or worsening over time.
--
-- Approach: built step by step using temporary tables so each
-- stage of the logic can be checked independently before moving
-- to the next (a temp table only exists for this session and is
-- dropped automatically when the connection closes).
--   customer_orders   -> every non-canceled order, with its month
--   customer_cohorts  -> each customer's first-purchase month
--   cohort_activity   -> every order tagged with "months since
--                        that customer's first purchase"
--   cohort_sizes      -> how many customers started in each cohort
-- ============================================================

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 6.1 PREVIEW: FIRST PURCHASE MONTH PER CUSTOMER
-- Quick look at the core logic before building it into a temp
-- table: customer_unique_id (the real person, not the per-order
-- customer_id) mapped to their earliest order month. Canceled/
-- unavailable orders are excluded since they were never fulfilled
-- and shouldn't count as a "purchase."
-- LIMIT 20 here is just to sanity-check the output looks right.
-- ------------------------------------------------------------
SELECT
    c.customer_unique_id,
    MIN(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01')) AS cohort_month
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_unique_id
LIMIT 20;

-- ------------------------------------------------------------
-- 6.2 BUILD BASE TABLE: customer_orders
-- One row per valid (non-canceled) order, with order_month
-- pre-computed as the 1st of that order's month. This is the
-- foundation every later temp table builds on.
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS customer_orders;

CREATE TEMPORARY TABLE customer_orders AS
SELECT
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp,
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS order_month
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('canceled', 'unavailable');

-- Row count sanity check - should roughly match total orders
-- minus canceled/unavailable ones.
SELECT COUNT(*) FROM customer_orders;

-- ------------------------------------------------------------
-- 6.3 BUILD: customer_cohorts
-- Collapses customer_orders down to one row per customer: their
-- cohort_month is simply the earliest order_month they appear in.
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS customer_cohorts;

CREATE TEMPORARY TABLE customer_cohorts AS
SELECT
    customer_unique_id,
    MIN(order_month) AS cohort_month
FROM customer_orders
GROUP BY customer_unique_id;

-- ------------------------------------------------------------
-- 6.4 BUILD: cohort_activity
-- Joins every order back to its customer's cohort_month, then
-- uses TIMESTAMPDIFF to calculate "months_since_first_purchase"
-- for that specific order. A value of 0 means "this is the same
-- month as their first purchase"; 1 means "one month later," etc.
-- This is the table the actual retention % calculations run on.
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS cohort_activity;

CREATE TEMPORARY TABLE cohort_activity AS
SELECT
    co.customer_unique_id,
    cc.cohort_month,
    co.order_month,
    TIMESTAMPDIFF(MONTH, cc.cohort_month, co.order_month) AS months_since_first_purchase
FROM customer_orders co
JOIN customer_cohorts cc ON co.customer_unique_id = cc.customer_unique_id;

-- Row count sanity check - should equal the row count of
-- customer_orders, since every order gets exactly one row here.
SELECT COUNT(*) FROM cohort_activity;

-- ------------------------------------------------------------
-- 6.5 PREVIEW: ACTIVE CUSTOMERS PER COHORT PER MONTH-OFFSET
-- Before computing percentages, look at the raw counts: for each
-- cohort_month, how many distinct customers were active at each
-- months_since_first_purchase value. LIMIT 30 is just to preview
-- a manageable slice of the full result.
-- ------------------------------------------------------------
SELECT
    cohort_month,
    months_since_first_purchase,
    COUNT(DISTINCT customer_unique_id) AS active_customers
FROM cohort_activity
GROUP BY cohort_month, months_since_first_purchase
ORDER BY cohort_month, months_since_first_purchase
LIMIT 30;

-- ------------------------------------------------------------
-- 6.6 BUILD: cohort_sizes
-- The denominator for every retention % calculation: how many
-- customers were in each cohort to begin with (i.e. active at
-- months_since_first_purchase = 0, their very first purchase month).
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS cohort_sizes;

CREATE TEMPORARY TABLE cohort_sizes AS
SELECT
    cohort_month,
    COUNT(DISTINCT customer_unique_id) AS total_customers
FROM cohort_activity
WHERE months_since_first_purchase = 0
GROUP BY cohort_month;

-- ------------------------------------------------------------
-- 6.7 THE RETENTION TABLE (the classic cohort grid)
-- For every cohort_month and every months_since_first_purchase
-- value, shows what % of that cohort's original size was still
-- active. This is the table you'd typically pivot into the classic
-- "cohort triangle" chart for a portfolio README.
-- ------------------------------------------------------------
SELECT
    ca.cohort_month,
    ca.months_since_first_purchase,
    COUNT(DISTINCT ca.customer_unique_id) AS active_customers,
    cs.total_customers,
    ROUND(COUNT(DISTINCT ca.customer_unique_id) * 100.0 / cs.total_customers, 2) AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, ca.months_since_first_purchase, cs.total_customers
ORDER BY ca.cohort_month, ca.months_since_first_purchase;

-- ------------------------------------------------------------
-- 6.8 OVERALL REPEAT PURCHASE RATE (single headline number)
-- Collapses everything down to one summary stat: of all customers
-- who ever ordered, what % placed more than one distinct order
-- (regardless of when). This is the number most useful for a
-- resume bullet point.
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS repeat_purchase_rate
FROM (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS order_count
    FROM customer_orders
    GROUP BY customer_unique_id
) customer_order_counts;

-- ------------------------------------------------------------
-- 6.9 REPEAT RATE BY COHORT (has retention improved over time?)
-- Unlike 6.7 (which breaks retention out by exact month-offset),
-- this collapses "any purchase after month 0" into a single repeat
-- rate per cohort. Comparing this rate across cohort_month values
-- answers the roadmap's question: has retention gotten better or
-- worse across the 2016-2018 period?
-- ------------------------------------------------------------
SELECT
    ca.cohort_month,
    cs.total_customers AS cohort_size,
    COUNT(DISTINCT CASE WHEN ca.months_since_first_purchase >= 1 THEN ca.customer_unique_id END) AS repeat_customers,
    ROUND(COUNT(DISTINCT CASE WHEN ca.months_since_first_purchase >= 1 THEN ca.customer_unique_id END) * 100.0 / cs.total_customers, 2) AS repeat_rate_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.total_customers
ORDER BY ca.cohort_month;

-- ============================================================
-- End of Phase 6.
-- Next: Phase 7 - additional analysis (reviews, sellers, payments, AOV).
-- ============================================================
