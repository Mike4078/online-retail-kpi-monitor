-- =============================================================================
-- 06_anomaly_detection.sql
-- Automated checks that catch unusual KPI movements, plus the investigation
-- of what was found. vw_daily_completeness feeds the Power BI Data Quality page.
-- =============================================================================

-- A-01  Daily orders vs trailing average of the same weekday (previous 4 weeks)
--       Flag days more than 35% above or below. Orders are used rather than
--       revenue because daily revenue swings a lot with a few expensive items
--       (tested: a revenue-based check flagged ~90 days, mostly noise).
WITH daily AS (
    SELECT d.date, d.weekday_name,
           COUNT(DISTINCT CASE WHEN f.status <> 'cancelled' THEN f.order_id END) AS orders
    FROM dim_date d
    LEFT JOIN fct_order_items f ON f.order_date = d.date
    GROUP BY d.date, d.weekday_name
),
with_baseline AS (
    SELECT date, weekday_name, orders,
           AVG(orders) OVER (PARTITION BY weekday_name ORDER BY date
                             ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS baseline
    FROM daily
)
SELECT date, weekday_name,
       orders,
       ROUND(baseline, 1) AS baseline,
       ROUND(100.0 * (orders - baseline) / baseline, 1) AS deviation_pct,
       CASE WHEN orders < baseline THEN 'DROP' ELSE 'SPIKE' END AS flag
FROM with_baseline
WHERE date >= '2025-02-01'                           -- need 4 weeks of history first
  AND (orders < baseline * 0.65 OR orders > baseline * 1.35)
ORDER BY date;
-- Finding: spikes in Black Friday week and drops after the 20 Dec shipping
-- cut-off are explained by the calendar. The drops in 9-15 Mar 2026 are not.


-- A-02  Same check by platform: is one platform behind the March drop?
WITH daily AS (
    SELECT d.date, d.weekday_name, p.platform,
           COUNT(DISTINCT f.order_id) AS orders
    FROM dim_date d
    CROSS JOIN (SELECT 'web' AS platform UNION ALL SELECT 'app') p
    LEFT JOIN fct_order_items f ON f.order_date = d.date
                               AND f.platform = p.platform
                               AND f.status <> 'cancelled'
    GROUP BY d.date, d.weekday_name, p.platform
)
SELECT date, platform, orders,
       ROUND(AVG(orders) OVER (PARTITION BY platform, weekday_name ORDER BY date
                               ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING)) AS baseline_orders
FROM daily
WHERE date BETWEEN '2026-03-02' AND '2026-03-22'
ORDER BY platform, date;
-- Finding: web orders are normal; APP orders are exactly 0 from 9 to 15 Mar.

--   Business or data problem? Evidence:
--   1) a real demand drop never goes to exactly zero for a whole week;
--   2) web orders and GA4 traffic were normal that week;
--   3) the 319 orphan order lines (DQ-02) belong to order_ids from exactly
--      that week - the lines were loaded, the order headers were not.
SELECT
    (SELECT COUNT(*) FROM raw_order_items
      WHERE order_id NOT IN (SELECT order_id FROM raw_orders))           AS orphan_lines,
    (SELECT MIN(order_date) || ' to ' || MAX(order_date) FROM stg_orders
      WHERE order_id BETWEEN 925686 AND 926123)                          AS dates_of_surrounding_orders,
    (SELECT ROUND(SUM(i.quantity * ABS(i.unit_price_czk) - i.discount_czk))
       FROM raw_order_items i
      WHERE i.order_id NOT IN (SELECT order_id FROM raw_orders))         AS missing_revenue_czk;
-- Conclusion: DATA problem (ingestion failure). Revenue for that week is
-- understated - flag it on the dashboard and ask the DWH team to reload.


-- A-03  GA4 tracking outage: backend web orders exist but GA4 has no sessions
SELECT m.date,
       SUM(m.backend_web_orders) AS backend_web_orders,
       SUM(m.sessions)           AS ga4_sessions
FROM fct_daily_marketing m
GROUP BY m.date
HAVING SUM(m.backend_web_orders) > 0 AND SUM(m.sessions) = 0
ORDER BY m.date;


-- -----------------------------------------------------------------------------
-- vw_daily_completeness  (Power BI Data Quality page)
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_daily_completeness;
CREATE VIEW vw_daily_completeness AS
WITH daily AS (
    SELECT d.date, d.weekday_name,
           COUNT(DISTINCT CASE WHEN f.platform = 'web' THEN f.order_id END) AS web_orders,
           COUNT(DISTINCT CASE WHEN f.platform = 'app' THEN f.order_id END) AS app_orders
    FROM dim_date d
    LEFT JOIN fct_order_items f ON f.order_date = d.date AND f.status <> 'cancelled'
    GROUP BY d.date, d.weekday_name
),
ga4 AS (
    SELECT date, SUM(sessions) AS ga4_sessions FROM stg_ga4_daily_traffic GROUP BY date
)
SELECT daily.date,
       daily.web_orders,
       daily.app_orders,
       COALESCE(ga4.ga4_sessions, 0) AS ga4_sessions,
       CASE
           WHEN COALESCE(ga4.ga4_sessions, 0) = 0 AND daily.web_orders > 0 THEN 'GA4 data missing'
           WHEN daily.app_orders = 0 AND daily.web_orders > 0           THEN 'App orders missing'
           ELSE 'OK'
       END AS data_status
FROM daily
LEFT JOIN ga4 ON ga4.date = daily.date;

SELECT data_status, COUNT(*) AS days, MIN(date) AS first_day, MAX(date) AS last_day
FROM vw_daily_completeness
GROUP BY data_status;


-- A-04  z-score anomaly detection -> done in notebooks/01_exploration.ipynb
--       (pandas rolling().std() is simpler than computing it in SQLite)
