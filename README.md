# E-Commerce Delivery Performance and Customer Retention Analysis

An end-to-end SQL analysis of the Brazilian E-Commerce Public Dataset by Olist (via Kaggle), covering data cleaning, delivery funnel analysis, cohort retention, customer segmentation, seller performance, and broader business insights — built in MySQL.

This project was built as a hands-on SQL learning exercise, with guidance on best practices for joins, window functions, CTEs, and data-quality checks along the way.

## Dataset

Source: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle), covering ~99,000 orders placed between 2016-2018 across multiple Brazilian marketplaces.

## Project Structure

| File | Description |
|---|---|
| `01_environment_setup.sql` | MySQL environment and schema setup |
| `02_schema_creation.sql` | Table creation with primary/foreign keys |
| `03_data_import.sql` | CSV import via `LOAD DATA LOCAL INFILE` |
| `04_data_cleaning_validation.sql` | Null checks, orphan records, duplicates, category translation, outlier checks |
| `05_delivery_funnel_analysis.sql` | Order-to-delivery funnel, on-time vs. late delivery by state/category/seller |
| `06_cohort_retention_analysis.sql` | Monthly cohort retention and repeat purchase rate (2016-2018) |
| `07_additional_analysis.sql` | Review/delivery correlation, seller ranking, payment methods, AOV by category, geographic analysis, RFM customer segmentation |

## Key Business Insights

### Data Quality
- **The dataset is clean at the referential level** — zero orphan records and zero duplicate rows across orders, order items, payments, and reviews, confirming the import process preserved full data integrity. A small number of genuine anomalies (8 orders marked "delivered" with no delivery date, ~0.008% of delivered orders) were identified and explicitly excluded from delivery-time calculations rather than silently ignored.

### Delivery Performance
- **91.88% of orders are delivered on time**, with late orders averaging 8.9 days overdue (worst case: 188 days). Delivery delays are heavily concentrated in Brazil's Northeast/North states (e.g., Alagoas at 23.9% late) versus the South/Southeast — a pattern attributable to distance from Olist's Southeast-concentrated fulfillment network.
- **Bulky and fragile categories consistently underperform on delivery** — furniture, home comfort, and audio show the highest late-delivery rates (12-17%), likely due to longer handling and shipping times.
- **A small number of high-volume sellers combine strong revenue with poor delivery performance** (e.g., one seller generating R$36K+ in revenue with a 23.6% late rate) — concrete, named targets for seller-management intervention.

### Customer Retention
- **Olist operates almost entirely as a one-time-purchase marketplace** — only 3.04% of customers (2,888 of 94,990) ever placed a second order. Retention remained roughly flat across 2016-2018 rather than declining, once accounting for the shorter observation window naturally available to later cohorts.

### Review & Satisfaction
- **Late deliveries devastate customer satisfaction** — orders delivered late average a 2.57-star review vs. 4.29 stars on-time, a nearly 1.7-star gap. Even 1-3 days late drops scores to 3.29, showing customers are sensitive to any lateness, not just severe delays.

### Seller & Category Economics
- **Revenue leaders and quality leaders are different sellers** — top-revenue sellers post decent-but-unremarkable ratings (3.4-4.4★), while several smaller-volume sellers achieve near-perfect 4.9-5.0★ ratings and 100% on-time delivery.
- **Credit card dominates payments and drives higher spend** — used in 74% of transactions, it's the only method offering installments (avg. 3.5), and correlates with the highest average order value.
- **A handful of high-ticket categories punch above their weight** — while bed/bath/table and health & beauty lead through order volume, niche categories like computers generate outsized revenue per order (avg. ₹1,147/item vs. ₹100-200 typical).

### Geography
- **São Paulo alone drives 37.4% of national revenue** — more than the next three states combined — highlighting significant geographic concentration, with an opportunity to grow underrepresented regions showing higher average order values.

### Customer Segmentation
- **RFM segmentation confirms Olist's customer base is dominated by low-frequency, one-time buyers** — with only 3.04% of customers ever repurchasing, the Frequency dimension carries little discriminating power, and segmentation is driven almost entirely by Recency and Monetary value. Just 1.4% of customers (1,286) qualify as "Champions," yet they spend more than double the average of other segments (₹350.77 vs. ₹156-172) — a small, high-value cohort worth prioritizing for retention campaigns.

## Tools Used

MySQL 8.0, MySQL Workbench

## Author

Darshil Bhansali
