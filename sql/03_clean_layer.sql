-- =============================================================================
-- 03_clean_layer.sql
-- Builds cleaned staging tables (stg_) from the raw layer.
-- Every rule is referenced by ID (C-xx) and documented in
-- docs/data_dictionary.md -> "Cleaning rules".
-- Nothing is deleted silently: excluded rows keep a flag column.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- stg_products
-- C-01: missing category -> derived from brand (each brand belongs to exactly
--       one category); 'Unknown' only if the brand can't be matched.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_products;
CREATE TABLE stg_products AS
WITH brand_category AS (
    SELECT brand, MIN(category) AS category
    FROM raw_products
    WHERE category IS NOT NULL AND TRIM(category) <> ''
    GROUP BY brand
)
SELECT
    p.product_id,
    TRIM(p.product_name)                                    AS product_name,
    COALESCE(NULLIF(TRIM(p.category), ''), bc.category, 'Unknown') AS category,
    CASE WHEN p.category IS NULL OR TRIM(p.category) = '' THEN 1 ELSE 0 END AS category_was_missing,
    TRIM(p.brand)                                           AS brand,
    p.list_price_czk,
    p.unit_cost_czk,
    DATE(p.launch_date)                                     AS launch_date
FROM raw_products p
LEFT JOIN brand_category bc ON bc.brand = p.brand;


-- -----------------------------------------------------------------------------
-- stg_customers
-- C-02: city spelling standardised (Praha / Brno variants)
-- C-03: missing region -> derived from the (cleaned) city
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_customers;
CREATE TABLE stg_customers AS
WITH cleaned AS (
    SELECT
        customer_id,
        DATE(signup_date) AS signup_date,
        NULLIF(TRIM(region), '') AS region,
        CASE
            WHEN LOWER(TRIM(city)) IN ('praha', 'prague')
              OR LOWER(TRIM(city)) LIKE 'praha %'  THEN 'Praha'
            WHEN LOWER(TRIM(city)) LIKE 'brno%'    THEN 'Brno'
            ELSE TRIM(city)
        END AS city,
        age_band,
        email_opt_in,
        acquisition_channel
    FROM raw_customers
),
city_region AS (            -- most common region for each city
    SELECT city, region
    FROM (
        SELECT city, region,
               ROW_NUMBER() OVER (PARTITION BY city ORDER BY COUNT(*) DESC) AS rn
        FROM cleaned
        WHERE region IS NOT NULL
        GROUP BY city, region
    )
    WHERE rn = 1
)
SELECT
    c.customer_id,
    c.signup_date,
    COALESCE(c.region, cr.region, 'Unknown')   AS region,
    CASE WHEN c.region IS NULL THEN 1 ELSE 0 END AS region_was_missing,
    c.city,
    c.age_band,
    c.email_opt_in,
    c.acquisition_channel
FROM cleaned c
LEFT JOIN city_region cr ON cr.city = c.city;


-- -----------------------------------------------------------------------------
-- stg_orders
-- C-04: Czech timestamps 'DD.MM.YYYY HH:MM' -> 'YYYY-MM-DD HH:MM:SS'
-- C-05: status -> LOWER(TRIM(status))
-- C-06: duplicates -> one row per order_id
-- C-07: QA test orders flagged (is_test_order = 1)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_orders;
CREATE TABLE stg_orders AS
WITH cleaned AS (
    SELECT
        order_id,
        customer_id,
        CASE
            WHEN order_ts LIKE '__.__.____ __:__'
            THEN SUBSTR(order_ts, 7, 4) || '-' || SUBSTR(order_ts, 4, 2) || '-' ||
                 SUBSTR(order_ts, 1, 2) || ' ' || SUBSTR(order_ts, 12, 5) || ':00'
            ELSE order_ts
        END                                   AS order_ts,
        CASE WHEN order_ts LIKE '__.__.____ __:__' THEN 1 ELSE 0 END AS ts_was_converted,
        platform,
        device,
        traffic_source,
        traffic_medium,
        COALESCE(campaign_id, '(not set)')    AS campaign_id,
        LOWER(TRIM(status))                   AS status,
        discount_code,
        shipping_fee_czk
    FROM raw_orders
),
deduped AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY ts_was_converted, order_ts) AS rn
    FROM cleaned
)
SELECT
    order_id,
    customer_id,
    order_ts,
    DATE(order_ts)                            AS order_date,
    ts_was_converted,
    platform,
    device,
    traffic_source,
    traffic_medium,
    traffic_source || ' / ' || traffic_medium AS channel_key,
    campaign_id,
    status,
    discount_code,
    shipping_fee_czk,
    CASE WHEN customer_id = 99999 OR discount_code = 'QA_TEST' THEN 1 ELSE 0 END AS is_test_order
FROM deduped
WHERE rn = 1;


-- -----------------------------------------------------------------------------
-- stg_order_items
-- C-08: negative unit price = sign error -> ABS()
-- C-09: quantity <= 0 -> is_valid = 0 (excluded from reporting)
-- C-10: orphan items (no matching order) -> is_orphan = 1 (excluded)
-- C-11: lines of QA test orders -> excluded via stg_orders.is_test_order
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_order_items;
CREATE TABLE stg_order_items AS
SELECT
    i.order_item_id,
    i.order_id,
    i.product_id,
    i.quantity,
    ABS(i.unit_price_czk)                                       AS unit_price_czk,
    CASE WHEN i.unit_price_czk < 0 THEN 1 ELSE 0 END            AS price_sign_fixed,
    i.discount_czk,
    i.quantity * ABS(i.unit_price_czk)                          AS gross_revenue_czk,
    ROUND(i.quantity * ABS(i.unit_price_czk) - i.discount_czk, 2) AS net_revenue_czk,
    ROUND(i.quantity * p.unit_cost_czk, 2)                      AS cost_czk,
    CASE WHEN o.order_id IS NULL THEN 1 ELSE 0 END              AS is_orphan,
    CASE WHEN i.quantity > 0
          AND o.order_id IS NOT NULL
          AND o.is_test_order = 0
         THEN 1 ELSE 0 END                                      AS is_valid
FROM raw_order_items i
LEFT JOIN stg_orders   o ON o.order_id   = i.order_id
LEFT JOIN stg_products p ON p.product_id = i.product_id;


-- -----------------------------------------------------------------------------
-- Light cleaning for marketing sources
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_ga4_daily_traffic;
CREATE TABLE stg_ga4_daily_traffic AS
SELECT
    DATE(date)                                         AS date,
    TRIM(session_source) || ' / ' || TRIM(session_medium) AS channel_key,
    COALESCE(session_campaign_id, '(not set)')          AS campaign_id,
    device,
    sessions,
    engaged_sessions,
    purchases,
    purchase_revenue
FROM raw_ga4_daily_traffic;

DROP TABLE IF EXISTS stg_ad_spend;
CREATE TABLE stg_ad_spend AS
SELECT
    DATE(date)                       AS date,
    source || ' / ' || medium        AS channel_key,
    campaign_id,
    campaign_name,
    spend_czk,
    clicks
FROM raw_ad_spend;

DROP TABLE IF EXISTS stg_email_campaigns;
CREATE TABLE stg_email_campaigns AS
SELECT campaign_id, campaign_name, DATE(send_date) AS send_date, segment, theme
FROM raw_email_campaigns;

DROP TABLE IF EXISTS stg_email_events;
CREATE TABLE stg_email_events AS
SELECT event_id, campaign_id, customer_id, LOWER(TRIM(event_type)) AS event_type,
       event_ts, DATE(event_ts) AS event_date
FROM raw_email_events;


-- -----------------------------------------------------------------------------
-- Checks: the clean layer must pass these (all should return 0)
-- -----------------------------------------------------------------------------
SELECT 'duplicate order_ids'   AS test, COUNT(*) - COUNT(DISTINCT order_id) AS failures FROM stg_orders
UNION ALL SELECT 'NULL order_date',     COUNT(*) FROM stg_orders WHERE order_date IS NULL
UNION ALL SELECT 'bad status',          COUNT(*) FROM stg_orders WHERE status NOT IN ('completed','cancelled','returned')
UNION ALL SELECT 'negative prices',     COUNT(*) FROM stg_order_items WHERE unit_price_czk < 0
UNION ALL SELECT 'Unknown category',    COUNT(*) FROM stg_products WHERE category = 'Unknown'
UNION ALL SELECT 'Unknown region',      COUNT(*) FROM stg_customers WHERE region = 'Unknown'
UNION ALL SELECT 'city variants left',  COUNT(*) FROM stg_customers WHERE city IN ('praha','Prague','PRAHA','Praha 5','brno','BRNO','Brno-střed');

-- How many item rows are excluded, and why?  (goes into the DQ log)
SELECT is_valid, is_orphan, COUNT(*) AS item_rows
FROM stg_order_items
GROUP BY is_valid, is_orphan;