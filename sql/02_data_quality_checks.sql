-- =============================================================================
-- 02_data_quality_checks.sql
-- Profiles the RAW layer before any cleaning. Each check answers one question
-- and its result is recorded in docs/data_quality_log.md.
-- The final statement creates vw_dq_scorecard, used on the Power BI
-- "Data Quality" page.
-- =============================================================================

-- DQ-00  Row counts per raw table (baseline)
SELECT 'raw_customers' AS table_name, COUNT(*) AS row_count FROM raw_customers
UNION ALL SELECT 'raw_products',          COUNT(*) FROM raw_products
UNION ALL SELECT 'raw_orders',            COUNT(*) FROM raw_orders
UNION ALL SELECT 'raw_order_items',       COUNT(*) FROM raw_order_items
UNION ALL SELECT 'raw_ga4_daily_traffic', COUNT(*) FROM raw_ga4_daily_traffic
UNION ALL SELECT 'raw_email_campaigns',   COUNT(*) FROM raw_email_campaigns
UNION ALL SELECT 'raw_email_events',      COUNT(*) FROM raw_email_events
UNION ALL SELECT 'raw_ad_spend',          COUNT(*) FROM raw_ad_spend;


-- DQ-01  Uniqueness: duplicate order_ids
--   total_rows - distinct_ids = number of extra (duplicate) rows
SELECT COUNT(*)                            AS total_rows,
       COUNT(DISTINCT order_id)            AS distinct_order_ids,
       COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_rows
FROM raw_orders;

--   Are the duplicates identical, or do the copies differ?
--   (rows with the same order_id but a different status or timestamp spelling)
SELECT order_id,
       COUNT(*)                   AS copies,
       COUNT(DISTINCT status)     AS distinct_status_values,
       COUNT(DISTINCT order_ts)   AS distinct_ts_values
FROM raw_orders
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY distinct_status_values DESC, distinct_ts_values DESC
LIMIT 20;
-- Finding: copies differ only in formatting (status case / timestamp format),
-- so they are the same order loaded twice -> keep one row per order_id.


-- DQ-02  Referential integrity: order_items without a matching order
SELECT COUNT(*)              AS orphan_items,
       COUNT(DISTINCT order_id) AS missing_orders,
       MIN(order_id)         AS min_order_id,
       MAX(order_id)         AS max_order_id
FROM raw_order_items
WHERE order_id NOT IN (SELECT order_id FROM raw_orders);

--   Which dates and platforms surround that order_id range?
--   (order_ids are assigned in time order, so neighbours tell us the date)
SELECT DATE(order_ts) AS order_date,
       platform,
       COUNT(*)       AS orders_present
FROM raw_orders
WHERE order_id BETWEEN 925686 AND 926123
  AND order_ts LIKE '____-__-__%'
GROUP BY 1, 2
ORDER BY 1, 2;
-- Finding: the orphans sit in 9-15 Mar 2026, and in that range only WEB orders
-- exist - every APP order for that week is missing from raw_orders.
-- This is an ingestion failure, not a business drop.


-- DQ-03  Referential integrity: orders whose customer is not in raw_customers
SELECT o.customer_id,
       COUNT(*)                 AS orders,
       GROUP_CONCAT(DISTINCT o.discount_code) AS discount_codes
FROM raw_orders o
LEFT JOIN raw_customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
GROUP BY o.customer_id;
-- Finding: 14 orders from customer 99999 with code QA_TEST = internal test orders.


-- DQ-04  Validity: status values
SELECT '[' || status || ']' AS status_value,   -- brackets make trailing spaces visible
       COUNT(*)              AS rows
FROM raw_orders
GROUP BY status
ORDER BY rows DESC;


-- DQ-05  Validity: timestamps not in ISO format 'YYYY-MM-DD HH:MM:SS'
SELECT COUNT(*) AS non_iso_timestamps,
       MIN(order_ts) AS example
FROM raw_orders
WHERE order_ts NOT LIKE '____-__-__ __:__:__';
-- Finding: they are Czech format 'DD.MM.YYYY HH:MM'. DATE() returns NULL for
-- them, so these orders would silently disappear from every date filter.


-- DQ-06  Validity: zero/negative quantity or price
SELECT SUM(CASE WHEN quantity <= 0       THEN 1 ELSE 0 END) AS zero_or_negative_qty,
       SUM(CASE WHEN unit_price_czk <= 0 THEN 1 ELSE 0 END) AS zero_or_negative_price
FROM raw_order_items;

--   Are negative prices just a sign error? Compare with the product list price.
SELECT i.order_item_id, i.unit_price_czk, p.list_price_czk
FROM raw_order_items i
JOIN raw_products p ON p.product_id = i.product_id
WHERE i.unit_price_czk < 0
LIMIT 10;
-- Finding: ABS(price) matches the list price (or list +8% for Electronics) -> sign error.


-- DQ-07  Outliers: price far from the product list price (excluding sign errors)
SELECT i.order_item_id, i.order_id, i.quantity, i.unit_price_czk, p.list_price_czk
FROM raw_order_items i
JOIN raw_products p ON p.product_id = i.product_id
WHERE i.unit_price_czk > 0
  AND (i.unit_price_czk > 2 * p.list_price_czk OR i.unit_price_czk < 0.5 * p.list_price_czk)
ORDER BY i.unit_price_czk DESC;
-- Finding: all outliers belong to the QA test orders (prices of 1 or 99,999 CZK).


-- DQ-08  Completeness: missing region / category
SELECT 'customers missing region' AS check_name,
       SUM(CASE WHEN region IS NULL OR TRIM(region) = '' THEN 1 ELSE 0 END) AS failed_rows,
       ROUND(100.0 * SUM(CASE WHEN region IS NULL OR TRIM(region) = '' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct
FROM raw_customers
UNION ALL
SELECT 'products missing category',
       SUM(CASE WHEN category IS NULL OR TRIM(category) = '' THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN category IS NULL OR TRIM(category) = '' THEN 1 ELSE 0 END) / COUNT(*), 1)
FROM raw_products;


-- DQ-09  Consistency: city spellings
SELECT '[' || city || ']' AS city_value,
       COUNT(*)           AS customers
FROM raw_customers
GROUP BY city
ORDER BY LOWER(TRIM(city)), customers DESC;
-- Finding: Praha appears as praha / Prague / PRAHA / 'Praha ' / Praha 5,
-- Brno as brno / BRNO / Brno-střed.


-- DQ-10  Completeness over time: days with no GA4 rows
WITH RECURSIVE cal(d) AS (
    SELECT DATE('2025-01-01')
    UNION ALL
    SELECT DATE(d, '+1 day') FROM cal WHERE d < '2026-06-30'
)
SELECT cal.d AS missing_ga4_date
FROM cal
LEFT JOIN (SELECT DISTINCT date FROM raw_ga4_daily_traffic) g ON g.date = cal.d
WHERE g.date IS NULL;
-- Finding: 4-6 May 2026 have no GA4 data at all (tracking outage).


-- DQ-11  Reconciliation: GA4 vs backend web revenue per day
WITH backend AS (
    SELECT DATE(o.order_ts) AS date,
           SUM(i.quantity * i.unit_price_czk - i.discount_czk) AS backend_revenue
    FROM (SELECT DISTINCT order_id, order_ts, platform, customer_id FROM raw_orders
          WHERE order_ts LIKE '____-__-__ __:__:__') o
    JOIN raw_order_items i ON i.order_id = o.order_id
    WHERE o.platform = 'web' AND o.customer_id <> 99999
    GROUP BY 1
),
ga4 AS (
    SELECT date, SUM(purchase_revenue) AS ga4_revenue
    FROM raw_ga4_daily_traffic
    GROUP BY 1
)
SELECT b.date,
       ROUND(b.backend_revenue, 0) AS backend_revenue,
       ROUND(g.ga4_revenue, 0)     AS ga4_revenue,
       ROUND(100.0 * (g.ga4_revenue - b.backend_revenue) / b.backend_revenue, 1) AS gap_pct
FROM backend b
LEFT JOIN ga4 g ON g.date = b.date
ORDER BY gap_pct;   -- worst days first (NULL gap = GA4 missing)
-- Finding: GA4 is normally 3-14% BELOW the backend (consent / ad blockers).
-- That is expected, so the backend is the source of truth for revenue.
-- Days with no GA4 value at all = the 4-6 May outage.


-- -----------------------------------------------------------------------------
-- DQ SCORECARD  (view -> exported to Power BI)
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_dq_scorecard;
CREATE VIEW vw_dq_scorecard AS
SELECT 'DQ-01' AS check_id, 'Duplicate order rows' AS check_name, 'raw_orders' AS table_name,
       (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM raw_orders) AS failed_rows,
       'Kept one row per order_id' AS action_taken
UNION ALL
SELECT 'DQ-02', 'Order items with no matching order', 'raw_order_items',
       (SELECT COUNT(*) FROM raw_order_items WHERE order_id NOT IN (SELECT order_id FROM raw_orders)),
       'Excluded from revenue; app orders 9-15 Mar 2026 missing - reported to DWH'
UNION ALL
SELECT 'DQ-03', 'Orders from unknown customer (QA test)', 'raw_orders',
       (SELECT COUNT(*) FROM raw_orders WHERE customer_id NOT IN (SELECT customer_id FROM raw_customers)),
       'Flagged as test orders and excluded'
UNION ALL
SELECT 'DQ-04', 'Non-standard status values', 'raw_orders',
       (SELECT COUNT(*) FROM raw_orders WHERE status NOT IN ('completed','cancelled','returned')),
       'Standardised with LOWER(TRIM())'
UNION ALL
SELECT 'DQ-05', 'Timestamps in Czech format', 'raw_orders',
       (SELECT COUNT(*) FROM raw_orders WHERE order_ts NOT LIKE '____-__-__ __:__:__'),
       'Converted to ISO format'
UNION ALL
SELECT 'DQ-06a', 'Negative unit price', 'raw_order_items',
       (SELECT COUNT(*) FROM raw_order_items WHERE unit_price_czk < 0),
       'Sign error - converted with ABS()'
UNION ALL
SELECT 'DQ-06b', 'Zero quantity', 'raw_order_items',
       (SELECT COUNT(*) FROM raw_order_items WHERE quantity <= 0),
       'Excluded (true quantity unknown)'
UNION ALL
SELECT 'DQ-07', 'Price outliers vs list price', 'raw_order_items',
       (SELECT COUNT(*) FROM raw_order_items i JOIN raw_products p ON p.product_id = i.product_id
        WHERE i.unit_price_czk > 0 AND (i.unit_price_czk > 2 * p.list_price_czk OR i.unit_price_czk < 0.5 * p.list_price_czk)),
       'All belong to QA test orders - excluded'
UNION ALL
SELECT 'DQ-08a', 'Customers missing region', 'raw_customers',
       (SELECT COUNT(*) FROM raw_customers WHERE region IS NULL OR TRIM(region) = ''),
       'Derived from city'
UNION ALL
SELECT 'DQ-08b', 'Products missing category', 'raw_products',
       (SELECT COUNT(*) FROM raw_products WHERE category IS NULL OR TRIM(category) = ''),
       'Derived from brand'
UNION ALL
SELECT 'DQ-09', 'Non-standard city spelling', 'raw_customers',
       (SELECT COUNT(*) FROM raw_customers WHERE city IN ('praha','Prague','Praha ','PRAHA','Praha 5','brno','Brno-střed','BRNO')),
       'Standardised to Praha / Brno'
UNION ALL
SELECT 'DQ-10', 'Days with no GA4 data', 'raw_ga4_daily_traffic',
       546 - (SELECT COUNT(DISTINCT date) FROM raw_ga4_daily_traffic),
       'Flagged on dashboard; conversion rate not shown for those days';

SELECT * FROM vw_dq_scorecard;