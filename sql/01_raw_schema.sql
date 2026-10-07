-- =============================================================================
-- 01_raw_schema.sql  |  RAW LAYER (provided)
-- Mirrors the source exports 1:1. No cleaning, no constraints: raw data is
-- loaded exactly as it arrives so problems can be found and documented.
-- Everything is stored as TEXT / loosely typed on purpose.
-- =============================================================================

DROP TABLE IF EXISTS raw_customers;
CREATE TABLE raw_customers (
    customer_id          INTEGER,
    signup_date          TEXT,      -- YYYY-MM-DD
    region               TEXT,      -- Czech kraj
    city                 TEXT,
    age_band             TEXT,
    email_opt_in         INTEGER,   -- 1 = consented to marketing emails
    acquisition_channel  TEXT
);

DROP TABLE IF EXISTS raw_products;
CREATE TABLE raw_products (
    product_id      INTEGER,
    product_name    TEXT,
    category        TEXT,
    brand           TEXT,
    list_price_czk  REAL,
    unit_cost_czk   REAL,
    launch_date     TEXT
);

DROP TABLE IF EXISTS raw_orders;
CREATE TABLE raw_orders (
    order_id          INTEGER,
    customer_id       INTEGER,
    order_ts          TEXT,       -- order timestamp (watch the formats!)
    platform          TEXT,       -- web / app
    device            TEXT,
    traffic_source    TEXT,
    traffic_medium    TEXT,
    campaign_id       TEXT,
    status            TEXT,       -- completed / cancelled / returned
    discount_code     TEXT,
    shipping_fee_czk  REAL
);

DROP TABLE IF EXISTS raw_order_items;
CREATE TABLE raw_order_items (
    order_item_id   INTEGER,
    order_id        INTEGER,
    product_id      INTEGER,
    quantity        INTEGER,
    unit_price_czk  REAL,         -- price actually charged per unit, before discount
    discount_czk    REAL          -- total discount on the line
);

DROP TABLE IF EXISTS raw_ga4_daily_traffic;
CREATE TABLE raw_ga4_daily_traffic (     -- GA4 export, WEB ONLY
    date                 TEXT,
    session_source       TEXT,
    session_medium       TEXT,
    session_campaign_id  TEXT,
    device               TEXT,
    sessions             INTEGER,
    engaged_sessions     INTEGER,
    purchases            INTEGER,           -- as tracked by GA4 (not the source of truth)
    purchase_revenue     REAL
);

DROP TABLE IF EXISTS raw_email_campaigns;
CREATE TABLE raw_email_campaigns (       -- Exponea campaign list
    campaign_id    TEXT,
    campaign_name  TEXT,
    send_date      TEXT,
    segment        TEXT,
    theme          TEXT
);

DROP TABLE IF EXISTS raw_email_events;
CREATE TABLE raw_email_events (          -- Exponea event export
    event_id     INTEGER,
    campaign_id  TEXT,
    customer_id  INTEGER,
    event_type   TEXT,                    -- sent / open / click / bounce / unsubscribe
    event_ts     TEXT
);

DROP TABLE IF EXISTS raw_ad_spend;
CREATE TABLE raw_ad_spend (              -- Google Ads + Meta Ads daily export
    date           TEXT,
    source         TEXT,
    medium         TEXT,
    campaign_id    TEXT,
    campaign_name  TEXT,
    spend_czk      REAL,
    clicks         INTEGER
);
