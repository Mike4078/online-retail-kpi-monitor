-- =============================================================================
-- 04_star_schema.sql  |  REPORTING LAYER
-- Star schema that Power BI connects to.
--   Facts:      fct_order_items      (grain: one row per order line)
--               fct_daily_marketing  (grain: date x channel x campaign)
--   Dimensions: dim_date, dim_customer, dim_product, dim_channel
-- Built only from stg_ tables. Test orders, orphan and invalid lines excluded.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dim_date
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
WITH RECURSIVE cal(d) AS (
    SELECT DATE('2025-01-01')
    UNION ALL
    SELECT DATE(d, '+1 day') FROM cal WHERE d < '2026-06-30'
)
SELECT
    d                                              AS date,
    CAST(STRFTIME('%Y', d) AS INTEGER)             AS year,
    CAST(STRFTIME('%m', d) AS INTEGER)             AS month,
    STRFTIME('%Y-%m', d)                           AS year_month,
    'Q' || ((CAST(STRFTIME('%m', d) AS INTEGER) + 2) / 3) AS quarter,
    STRFTIME('%Y', d) || '-Q' || ((CAST(STRFTIME('%m', d) AS INTEGER) + 2) / 3) AS year_quarter,
    DATE(d, '-6 days', 'weekday 1')                AS week_start,
    CASE CAST(STRFTIME('%w', d) AS INTEGER)
         WHEN 0 THEN 'Sun' WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue' WHEN 3 THEN 'Wed'
         WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri' ELSE 'Sat' END AS weekday_name,
    CASE WHEN STRFTIME('%w', d) IN ('0','6') THEN 1 ELSE 0 END AS is_weekend
FROM cal;


-- -----------------------------------------------------------------------------
-- dim_customer
--   Orders counted = non-test, non-cancelled (see KPI definitions)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer AS
WITH cust_orders AS (
    SELECT customer_id,
           MIN(order_date) AS first_order_date,
           COUNT(*)        AS lifetime_orders
    FROM stg_orders
    WHERE is_test_order = 0 AND status <> 'cancelled'
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.signup_date,
    STRFTIME('%Y-%m', c.signup_date)        AS signup_cohort,
    c.region,
    c.city,
    c.age_band,
    c.email_opt_in,
    c.acquisition_channel,
    co.first_order_date,
    STRFTIME('%Y-%m', co.first_order_date)  AS first_order_cohort,
    COALESCE(co.lifetime_orders, 0)         AS lifetime_orders,
    CASE WHEN co.lifetime_orders IS NULL THEN 'no orders'
         WHEN co.lifetime_orders = 1     THEN 'one-time'
         ELSE 'repeat' END                  AS customer_type
FROM stg_customers c
LEFT JOIN cust_orders co ON co.customer_id = c.customer_id;


-- -----------------------------------------------------------------------------
-- dim_product
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product AS
SELECT
    product_id,
    product_name,
    category,
    brand,
    list_price_czk,
    unit_cost_czk,
    CASE WHEN list_price_czk < 500  THEN '1. <500'
         WHEN list_price_czk < 1500 THEN '2. 500-1499'
         WHEN list_price_czk < 5000 THEN '3. 1500-4999'
         ELSE '4. 5000+' END AS price_band
FROM stg_products;


-- -----------------------------------------------------------------------------
-- dim_channel  (every source/medium seen in any source system)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_channel;
CREATE TABLE dim_channel AS
WITH all_channels AS (
    SELECT channel_key FROM stg_orders
    UNION SELECT channel_key FROM stg_ga4_daily_traffic
    UNION SELECT channel_key FROM stg_ad_spend
)
SELECT
    channel_key,
    SUBSTR(channel_key, 1, INSTR(channel_key, ' / ') - 1) AS source,
    SUBSTR(channel_key, INSTR(channel_key, ' / ') + 3)    AS medium,
    CASE SUBSTR(channel_key, INSTR(channel_key, ' / ') + 3)
         WHEN 'cpc'         THEN 'Paid Search'
         WHEN 'paid_social' THEN 'Paid Social'
         WHEN 'organic'     THEN 'Organic Search'
         WHEN '(none)'      THEN 'Direct'
         WHEN 'referral'    THEN 'Referral'
         WHEN 'email'       THEN 'Email'
         ELSE 'Other' END                                 AS channel_group
FROM all_channels;


-- -----------------------------------------------------------------------------
-- fct_order_items  (all statuses kept; measures filter on status)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS fct_order_items;
CREATE TABLE fct_order_items AS
WITH order_seq AS (
    SELECT order_id,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_ts, order_id) AS order_seq
    FROM stg_orders
    WHERE is_test_order = 0 AND status <> 'cancelled'
)
SELECT
    i.order_item_id,
    i.order_id,
    o.order_date,
    o.customer_id,
    i.product_id,
    o.channel_key,
    o.campaign_id,
    o.platform,
    o.device,
    o.status,
    o.discount_code,
    CASE WHEN s.order_seq = 1 THEN 1 ELSE 0 END AS is_first_order,
    i.quantity,
    i.gross_revenue_czk,
    i.discount_czk,
    i.net_revenue_czk,
    i.cost_czk,
    ROUND(i.net_revenue_czk - i.cost_czk, 2)   AS margin_czk
FROM stg_order_items i
JOIN stg_orders o      ON o.order_id = i.order_id
LEFT JOIN order_seq s  ON s.order_id = i.order_id
WHERE i.is_valid = 1;


-- -----------------------------------------------------------------------------
-- fct_daily_marketing  (date x channel x campaign)
--   Three sources aggregated to the same grain, stacked with UNION ALL and
--   summed. This keeps rows that exist in only one source (a JOIN would drop
--   e.g. spend on a day with no orders).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS fct_daily_marketing;
CREATE TABLE fct_daily_marketing AS
WITH ga4 AS (
    SELECT date, channel_key, campaign_id,
           SUM(sessions) AS sessions, SUM(purchases) AS ga4_purchases,
           SUM(purchase_revenue) AS ga4_revenue_czk,
           0 AS spend_czk, 0 AS ad_clicks,
           0 AS backend_orders, 0 AS backend_web_orders, 0 AS backend_revenue_czk
    FROM stg_ga4_daily_traffic
    GROUP BY 1, 2, 3
),
spend AS (
    SELECT date, channel_key, campaign_id,
           0, 0, 0,
           SUM(spend_czk), SUM(clicks),
           0, 0, 0
    FROM stg_ad_spend
    GROUP BY 1, 2, 3
),
backend AS (
    SELECT o.order_date, o.channel_key, o.campaign_id,
           0, 0, 0,
           0, 0,
           COUNT(DISTINCT o.order_id),
           COUNT(DISTINCT CASE WHEN o.platform = 'web' THEN o.order_id END),
           COALESCE(SUM(CASE WHEN o.status = 'completed' THEN f.net_revenue_czk END), 0)
    FROM stg_orders o
    LEFT JOIN fct_order_items f ON f.order_id = o.order_id
    WHERE o.is_test_order = 0 AND o.status <> 'cancelled'
    GROUP BY 1, 2, 3
),
stacked AS (
    SELECT * FROM ga4
    UNION ALL SELECT * FROM spend
    UNION ALL SELECT * FROM backend
)
SELECT
    date, channel_key, campaign_id,
    SUM(sessions)            AS sessions,
    SUM(ga4_purchases)       AS ga4_purchases,
    SUM(ga4_revenue_czk)     AS ga4_revenue_czk,
    SUM(spend_czk)           AS spend_czk,
    SUM(ad_clicks)           AS ad_clicks,
    SUM(backend_orders)      AS backend_orders,
    SUM(backend_web_orders)  AS backend_web_orders,
    SUM(backend_revenue_czk) AS backend_revenue_czk
FROM stacked
GROUP BY date, channel_key, campaign_id;


-- -----------------------------------------------------------------------------
-- Checks
-- -----------------------------------------------------------------------------
-- Mondays: date must equal week_start
SELECT date, weekday_name, week_start FROM dim_date WHERE weekday_name = 'Mon' LIMIT 3;

-- Totals must match between the two facts (completed net revenue)
SELECT
    (SELECT ROUND(SUM(net_revenue_czk)) FROM fct_order_items WHERE status = 'completed') AS fct_order_items_revenue,
    (SELECT ROUND(SUM(backend_revenue_czk)) FROM fct_daily_marketing)                   AS fct_daily_marketing_revenue;

-- Every fact row must find its dimensions (all should be 0)
SELECT 'missing product' AS test, COUNT(*) AS failures FROM fct_order_items f LEFT JOIN dim_product p ON p.product_id = f.product_id WHERE p.product_id IS NULL
UNION ALL SELECT 'missing customer', COUNT(*) FROM fct_order_items f LEFT JOIN dim_customer c ON c.customer_id = f.customer_id WHERE c.customer_id IS NULL
UNION ALL SELECT 'missing date',     COUNT(*) FROM fct_order_items f LEFT JOIN dim_date d ON d.date = f.order_date WHERE d.date IS NULL
UNION ALL SELECT 'missing channel',  COUNT(*) FROM fct_daily_marketing m LEFT JOIN dim_channel ch ON ch.channel_key = m.channel_key WHERE ch.channel_key IS NULL;
