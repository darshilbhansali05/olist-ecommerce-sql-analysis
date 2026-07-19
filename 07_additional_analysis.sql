-- ============================================================
-- PHASE 7: ADDITIONAL ANALYSIS
-- Project: Olist E-Commerce SQL Analysis
-- Purpose: Go beyond the core funnel/cohort work to answer a
--          few more business questions: does late delivery hurt
--          review scores? which sellers perform best? which
--          payment methods dominate? what's the AOV by category?
--          which states drive the most revenue? and finally, which
--          customers are most valuable / at risk of churning (RFM)?
--
-- Recurring pattern used below: order_reviews can contain more
-- than one review per order_id (see 7.1). To avoid double-counting
-- when joining reviews to orders, most queries use a ROW_NUMBER()
-- window function to pick just the SINGLE most recent review per
-- order (rn = 1) before joining - this is the standard "de-duplicate
-- via window function" pattern.
-- ============================================================

USE olist_ecommerce;

-- ------------------------------------------------------------
-- 7.1 CHECK: DO ANY ORDERS HAVE MULTIPLE REVIEWS?
-- Confirms whether order_reviews needs de-duplication before it's
-- safely joined to orders (a join with duplicates would inflate
-- order counts and skew the average review score).
-- ------------------------------------------------------------
SELECT order_id, COUNT(*)
FROM order_reviews
GROUP BY order_id
HAVING COUNT(*) > 1;

-- ------------------------------------------------------------
-- 7.2 REVIEW SCORE vs ON-TIME / LATE (SIMPLE VERSION)
-- Answers: does a late delivery correlate with a lower average
-- review score? ranked_reviews picks one review per order (the
-- most recently created one, via ROW_NUMBER() + rn = 1) so each
-- order contributes exactly once to the average.
-- ------------------------------------------------------------
WITH ranked_reviews AS (
    SELECT
        order_id,
        review_score,
        review_creation_date,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY review_creation_date DESC
        ) AS rn
    FROM order_reviews
)
SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status,
    COUNT(*) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders o
JOIN ranked_reviews r
    ON o.order_id = r.order_id
    AND r.rn = 1
WHERE o.order_status = 'delivered'
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY delivery_status;

-- ------------------------------------------------------------
-- 7.3 REVIEW SCORE vs LATENESS (BUCKETED VERSION)
-- More granular than 7.2: instead of a binary On Time/Late split,
-- buckets lateness into ranges (1-3 days, 4-7 days, etc.) to see
-- whether review scores drop off gradually or fall off a cliff
-- after a certain number of days late. review_id DESC is added as
-- a tiebreaker in case two reviews share the exact same
-- review_creation_date. The ORDER BY CASE at the end forces the
-- buckets to display in logical (not alphabetical) order.
-- ------------------------------------------------------------
WITH ranked_reviews AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY review_creation_date DESC, review_id DESC
        ) AS rn
    FROM order_reviews
)
SELECT
    CASE
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) <= 0
            THEN 'On Time'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 1 AND 3
            THEN '1-3 Days Late'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 4 AND 7
            THEN '4-7 Days Late'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 8 AND 14
            THEN '8-14 Days Late'
        ELSE '15+ Days Late'
    END AS delay_bucket,
    COUNT(*) AS total_orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders o
JOIN ranked_reviews r
    ON o.order_id = r.order_id
    AND r.rn = 1
WHERE o.order_status = 'delivered'
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY delay_bucket
ORDER BY
    CASE delay_bucket
        WHEN 'On Time' THEN 1
        WHEN '1-3 Days Late' THEN 2
        WHEN '4-7 Days Late' THEN 3
        WHEN '8-14 Days Late' THEN 4
        ELSE 5
    END;

-- ------------------------------------------------------------
-- 7.4 SELLER PERFORMANCE RANKING
-- Combines three signals per seller into one leaderboard: order
-- volume/revenue, average review score (via the same de-dup
-- pattern as 7.2/7.3, but LEFT JOIN since a seller's order might
-- have zero reviews), and % of their orders delivered on time.
-- HAVING total_orders >= 10 filters out sellers with too few
-- orders to draw a meaningful conclusion from.
-- Default sort here is by total_revenue - see the commented
-- alternative below to instead rank by review score / on-time %.
-- ------------------------------------------------------------
WITH ranked_reviews AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY review_creation_date DESC, review_id DESC
        ) AS rn
    FROM order_reviews
)
SELECT
    oi.seller_id,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(rr.review_score), 2) AS avg_review_score,
    ROUND(
        100 * COUNT(DISTINCT CASE
                WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
                THEN oi.order_id
             END) / COUNT(DISTINCT oi.order_id), 1
    ) AS pct_on_time_delivery
FROM order_items oi
JOIN orders o
    ON oi.order_id = o.order_id
LEFT JOIN ranked_reviews rr
    ON oi.order_id = rr.order_id
    AND rr.rn = 1
WHERE o.order_status = 'delivered'
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY oi.seller_id
HAVING total_orders >= 10
ORDER BY total_revenue DESC
LIMIT 20;

-- Alternative view: same CTE and SELECT as above, just re-ranked
-- to surface the BEST-rated / most reliable sellers instead of
-- the highest-revenue ones:
-- ORDER BY avg_review_score DESC, pct_on_time_delivery DESC
-- LIMIT 20;

-- ------------------------------------------------------------
-- 7.5 PAYMENT METHOD ANALYSIS - USAGE & VALUE
-- How often each payment_type is used, its share of all payments
-- (SUM(COUNT(*)) OVER () is a window function that computes the
-- grand total across all groups, letting each row divide by it to
-- get a %), and the typical payment value/installment count.
-- ------------------------------------------------------------
SELECT
    op.payment_type,
    COUNT(*) AS total_payments,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all_payments,
    ROUND(AVG(op.payment_value), 2) AS avg_payment_value,
    ROUND(AVG(op.payment_installments), 1) AS avg_installments,
    ROUND(SUM(op.payment_value), 2) AS total_value
FROM order_payments op
GROUP BY op.payment_type
ORDER BY total_payments DESC;

-- ------------------------------------------------------------
-- 7.6 PAYMENT METHOD vs ORDER VALUE
-- Some orders are split across multiple payment rows (e.g. part
-- voucher, part credit card). primary_payment picks the single
-- LARGEST payment_value row per order to represent "how this order
-- was mainly paid for," then joins to the true total order_value
-- (summed across all payment rows for that order) to see whether
-- certain payment methods correlate with bigger or smaller orders.
-- ------------------------------------------------------------
WITH primary_payment AS (
    SELECT
        order_id,
        payment_type,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY payment_value DESC
        ) AS rn
    FROM order_payments
)
SELECT
    pp.payment_type,
    COUNT(*) AS total_orders,
    ROUND(AVG(order_totals.order_value), 2) AS avg_order_value
FROM primary_payment pp
JOIN (
    SELECT order_id, SUM(payment_value) AS order_value
    FROM order_payments
    GROUP BY order_id
) order_totals
    ON pp.order_id = order_totals.order_id
WHERE pp.rn = 1
GROUP BY pp.payment_type
ORDER BY total_orders DESC;

-- ------------------------------------------------------------
-- 7.7 AVERAGE ORDER VALUE (AOV) BY PRODUCT CATEGORY
-- avg_item_value = average (price + freight_value) per line item
-- in that category. HAVING total_orders >= 30 again filters out
-- categories too small to be meaningful. Default sort is by order
-- volume - see the commented alternative to rank by revenue instead.
-- ------------------------------------------------------------
SELECT
    pt.product_category_name_english AS category,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(AVG(oi.price + oi.freight_value), 2) AS avg_item_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
JOIN product_category_name_translation pt
    ON p.product_category_name = pt.product_category_name
GROUP BY pt.product_category_name_english
HAVING total_orders >= 30
ORDER BY total_orders DESC
LIMIT 20;

-- Alternative view: same query, ranked by revenue instead of
-- order volume - useful for "which categories matter most to the
-- business" rather than "which are most popular":
-- ORDER BY total_revenue DESC
-- LIMIT 20;

-- ------------------------------------------------------------
-- 7.8 GEOGRAPHIC VIEW - REVENUE BY STATE
-- Which Brazilian states generate the most orders and revenue.
-- Restricted to order_status = 'delivered' to keep this aligned
-- with "revenue actually realized" rather than orders still in
-- progress or canceled.
-- ------------------------------------------------------------
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(SUM(oi.price + oi.freight_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC
LIMIT 15;

-- ------------------------------------------------------------
-- 7.9 GEOGRAPHIC VIEW - % SHARE OF NATIONAL REVENUE
-- Same base data as 7.8, but expressed as each state's % share of
-- total national revenue instead of a raw dollar amount - useful
-- for a quick "top 3 states make up X% of revenue" headline stat.
-- SUM(...) OVER () is a window function summing across ALL rows,
-- giving the national total that each state's revenue is divided by.
-- ------------------------------------------------------------
SELECT
    c.customer_state,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(
        100 * SUM(oi.price + oi.freight_value)
        / SUM(SUM(oi.price + oi.freight_value)) OVER (), 1
    ) AS pct_of_national_revenue
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC
LIMIT 15;

-- ------------------------------------------------------------
-- 7.10 RFM CUSTOMER SEGMENTATION
-- RFM = Recency, Frequency, Monetary - a classic marketing
-- framework that scores every customer on three dimensions and
-- groups them into actionable segments (who to reward, who's at
-- risk of churning, who's new, etc.). Built in two stages:
--
--   customer_orders (CTE): one row per customer_unique_id with
--     - last_order_date  -> Recency input (how recently did they buy?)
--     - frequency        -> how many distinct orders they placed
--     - monetary         -> total amount they've paid across all orders
--
--   rfm_scores (CTE): converts each raw metric into a 1-5 score
--     using NTILE(5), which splits customers into 5 equal-sized
--     buckets ("quintiles"). Recency is ordered DESC on the day-gap
--     (so customers who bought MOST RECENTLY - the smallest gap -
--     land in the highest score bucket); frequency and monetary are
--     ordered ASC (so the biggest spenders/most frequent buyers land
--     in the highest score bucket, 5).
--
-- NOTE ON THE HARDCODED DATE '2018-10-17':
-- This is used as the "reference/analysis date" for Recency (i.e.
-- "today", for the purpose of this calculation)
-- confirm this value with: SELECT MAX(order_purchase_timestamp) FROM orders;
-- and swap it in before relying on these results.


-- Final SELECT: buckets customers into 4 example segments based on
-- combinations of R/F/M scores (Champions = recent, frequent, big
-- spenders; At Risk = used to be frequent but haven't bought
-- recently; New Customers = recent but low frequency so far; Low
-- Engagement = everyone else). These segment rules are a starting
-- point - feel free to adjust the thresholds to fit what the data
-- shows.
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_order_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(op.payment_value) AS monetary
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_payments op ON o.order_id = op.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT
        customer_unique_id,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY DATEDIFF('2018-10-17', last_order_date) DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM customer_orders
)
SELECT
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score <= 2 AND f_score >= 4 THEN 'At Risk (was loyal)'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        ELSE 'Low Engagement'
    END AS customer_segment,
    COUNT(*) AS num_customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers,
    ROUND(AVG(monetary), 2) AS avg_spend
FROM rfm_scores
GROUP BY customer_segment
ORDER BY num_customers DESC;

-- ============================================================
-- End of Project.
-- ============================================================
