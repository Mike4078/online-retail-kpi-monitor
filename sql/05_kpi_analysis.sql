-- =============================================================================
-- 05_kpi_analysis.sql
-- Answers the stakeholder questions in docs/requirements.md using the star
-- schema. KPI definitions follow docs/data_dictionary.md:
--   Net revenue = net of discounts, COMPLETED orders only, excl. shipping
--   Orders      = non-cancelled orders (completed + returned)
--   AOV         = net revenue / completed orders
-- C-03 and C-04 are saved as views so Power BI can use them.
-- =============================================================================

-- ===== SALES ================================================================

-- S-01  Monthly net revenue, orders, AOV and month-over-month change
WITH monthly AS (
    SELECT d.year_month,
           SUM(CASE WHEN f.status = 'completed' THEN f.net_revenue_czk END)              AS net_revenue,
           COUNT(DISTINCT CASE WHEN f.status <> 'cancelled' THEN f.order_id END)          AS orders,
           COUNT(DISTINCT CASE WHEN f.status = 'completed' THEN f.order_id END)           AS completed_orders
    FROM fct_order_items f
    JOIN dim_date d ON d.date = f.order_date
    GROUP BY d.year_month
)
SELECT year_month,
       ROUND(net_revenue)                       AS net_revenue_czk,
       orders,
       ROUND(net_revenue / completed_orders)    AS aov_czk,
       ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY year_month))
             / LAG(net_revenue) OVER (ORDER BY year_month), 1) AS revenue_mom_pct
FROM monthly
ORDER BY year_month;
-- Answer: Orders grew +22% (H1 2026 vs H1 2025) but net revenue fell 2.3% because
--         AOV dropped from ~4,500 to ~3,700 CZK. Peak = Nov 2025 (Black Friday).
--         Mar 2026 is understated (missing app orders - see 06).


-- S-02  Revenue share and margin % by category per quarter
WITH q AS (
    SELECT d.year_quarter, p.category,
           SUM(f.net_revenue_czk) AS net_revenue,
           SUM(f.margin_czk)      AS margin
    FROM fct_order_items f
    JOIN dim_date d    ON d.date = f.order_date
    JOIN dim_product p ON p.product_id = f.product_id
    WHERE f.status = 'completed'
    GROUP BY 1, 2
)
SELECT year_quarter, category,
       ROUND(net_revenue)                                                   AS net_revenue_czk,
       ROUND(100.0 * net_revenue / SUM(net_revenue) OVER (PARTITION BY year_quarter), 1) AS revenue_share_pct,
       ROUND(100.0 * margin / net_revenue, 1)                               AS margin_pct
FROM q
ORDER BY category, year_quarter;
-- Answer: Electronics fell from 52.6% of revenue (2025-Q1) to 36.2% (2026-Q2).
--         Beauty (4.2% -> 9.8%), Sports and Home & Kitchen grew. Electronics has the
--         highest unit price (~4,000 CZK), so this mix shift explains the lower AOV.
--         Electronics margin % rose from ~42% to ~46%.


-- S-03  Top 10 products by margin, H1 2026 vs H2 2025 rank
WITH periods AS (
    SELECT f.product_id,
           SUM(CASE WHEN f.order_date BETWEEN '2026-01-01' AND '2026-06-30' THEN f.margin_czk ELSE 0 END) AS margin_h1_2026,
           SUM(CASE WHEN f.order_date BETWEEN '2025-07-01' AND '2025-12-31' THEN f.margin_czk ELSE 0 END) AS margin_h2_2025
    FROM fct_order_items f
    WHERE f.status = 'completed'
    GROUP BY f.product_id
),
ranked AS (
    SELECT product_id, margin_h1_2026, margin_h2_2025,
           RANK() OVER (ORDER BY margin_h1_2026 DESC) AS rank_h1_2026,
           RANK() OVER (ORDER BY margin_h2_2025 DESC) AS rank_h2_2025
    FROM periods
)
SELECT r.rank_h1_2026, r.rank_h2_2025,
       r.rank_h2_2025 - r.rank_h1_2026 AS rank_change,
       p.product_name, p.category,
       ROUND(r.margin_h1_2026) AS margin_h1_2026_czk
FROM ranked r
JOIN dim_product p ON p.product_id = r.product_id
WHERE r.rank_h1_2026 <= 10
ORDER BY r.rank_h1_2026;
-- Answer: Top 10 is dominated by Electronics; Linea Denim Jeans is now #1.
--         NordWear Denim Jeans dropped from #5 to #9 (high returns - see S-04).


-- S-04  Return rate by brand per quarter (Fashion shown; remove WHERE for all)
WITH orders_brand AS (
    SELECT DISTINCT d.year_quarter, p.category, p.brand, f.order_id, f.status
    FROM fct_order_items f
    JOIN dim_date d    ON d.date = f.order_date
    JOIN dim_product p ON p.product_id = f.product_id
    WHERE f.status IN ('completed', 'returned')
)
SELECT category, brand, year_quarter,
       COUNT(*)                                                         AS orders,
       ROUND(100.0 * SUM(CASE WHEN status = 'returned' THEN 1 ELSE 0 END) / COUNT(*), 1) AS return_rate_pct
FROM orders_brand
WHERE category = 'Fashion'
GROUP BY 1, 2, 3
ORDER BY brand, year_quarter;
-- Answer: NordWear's return rate jumped from 14-18% in 2025 to 24% in 2026-Q1
--         and 37% in 2026-Q2. Other Fashion brands stayed at 13-19%.


-- S-05  Black Friday week 2025 (24-30 Nov) vs average of the 4 previous weeks
WITH weekly AS (
    SELECT d.week_start,
           SUM(CASE WHEN f.status = 'completed' THEN f.net_revenue_czk END)  AS net_revenue,
           SUM(CASE WHEN f.status = 'completed' THEN f.margin_czk END)       AS margin,
           SUM(CASE WHEN f.status = 'completed' THEN f.discount_czk END)     AS discounts,
           COUNT(DISTINCT CASE WHEN f.status = 'completed' THEN f.order_id END) AS completed_orders
    FROM fct_order_items f
    JOIN dim_date d ON d.date = f.order_date
    WHERE d.week_start BETWEEN '2025-10-27' AND '2025-11-24'
    GROUP BY d.week_start
)
SELECT CASE WHEN week_start = '2025-11-24' THEN 'Black Friday week' ELSE 'Avg of 4 prior weeks' END AS period,
       ROUND(AVG(net_revenue))                           AS net_revenue_czk,
       ROUND(AVG(completed_orders))                      AS completed_orders,
       ROUND(SUM(net_revenue) / SUM(completed_orders))   AS aov_czk,
       ROUND(100.0 * SUM(margin) / SUM(net_revenue), 1)  AS margin_pct,
       ROUND(AVG(margin))                                AS margin_czk,
       ROUND(AVG(discounts))                             AS discounts_czk
FROM weekly
GROUP BY 1;
-- Answer: Black Friday week roughly doubled revenue (+97%) and orders (+134%).
--         Margin % fell from 45.1% to 35.8% because of 638k CZK in discounts, but
--         margin in CZK was still +56% vs a normal week -> profitable overall.


-- ===== CUSTOMERS / CRM ======================================================

-- C-01  New vs returning customer revenue per month
SELECT d.year_month,
       ROUND(SUM(CASE WHEN f.is_first_order = 1 THEN f.net_revenue_czk ELSE 0 END)) AS new_customer_revenue,
       ROUND(SUM(CASE WHEN f.is_first_order = 0 THEN f.net_revenue_czk ELSE 0 END)) AS returning_customer_revenue,
       ROUND(100.0 * SUM(CASE WHEN f.is_first_order = 0 THEN f.net_revenue_czk ELSE 0 END)
             / SUM(f.net_revenue_czk), 1)                                            AS returning_share_pct
FROM fct_order_items f
JOIN dim_date d ON d.date = f.order_date
WHERE f.status = 'completed'
GROUP BY d.year_month
ORDER BY d.year_month;
-- Answer: After the first months (when everyone is 'new' because the data
--         starts in Jan 2025), returning customers bring ~86-89% of revenue.


-- C-02  Repeat purchase rate within 90 days of first order
--       Only customers whose first order was at least 90 days before the end
--       of the data (2026-06-30), so everyone had a full 90 days to come back.
WITH orders AS (
    SELECT DISTINCT customer_id, order_id, order_date, platform, is_first_order
    FROM fct_order_items
    WHERE status <> 'cancelled'
),
first_orders AS (
    SELECT customer_id, order_date AS first_date, platform AS first_platform
    FROM orders WHERE is_first_order = 1
),
repeaters AS (
    SELECT DISTINCT fo.customer_id
    FROM first_orders fo
    JOIN orders o ON o.customer_id = fo.customer_id
                 AND o.is_first_order = 0
                 AND o.order_date <= DATE(fo.first_date, '+90 days')
)
SELECT c.acquisition_channel,
       fo.first_platform,
       COUNT(*)                                             AS new_customers,
       ROUND(100.0 * COUNT(r.customer_id) / COUNT(*), 1)    AS repeat_90d_pct
FROM first_orders fo
JOIN dim_customer c   ON c.customer_id = fo.customer_id
LEFT JOIN repeaters r ON r.customer_id = fo.customer_id
WHERE fo.first_date <= DATE('2026-06-30', '-90 days')
GROUP BY 1, 2
ORDER BY repeat_90d_pct DESC;
-- Answer: About 60-65% of new customers order again within 90 days.
--         Differences between acquisition channels and platforms are small.


-- C-03  Cohort retention (view): % of each first-order cohort ordering again
--       N months after their first order
DROP VIEW IF EXISTS vw_cohort_retention;
CREATE VIEW vw_cohort_retention AS
WITH orders AS (
    SELECT DISTINCT f.customer_id, STRFTIME('%Y-%m', f.order_date) AS order_month
    FROM fct_order_items f
    WHERE f.status <> 'cancelled'
),
cohort AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM orders GROUP BY customer_id
),
activity AS (
    SELECT c.cohort_month,
           (CAST(SUBSTR(o.order_month, 1, 4) AS INTEGER) * 12 + CAST(SUBSTR(o.order_month, 6, 2) AS INTEGER))
         - (CAST(SUBSTR(c.cohort_month, 1, 4) AS INTEGER) * 12 + CAST(SUBSTR(c.cohort_month, 6, 2) AS INTEGER)) AS months_since_first,
           o.customer_id
    FROM orders o
    JOIN cohort c ON c.customer_id = o.customer_id
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size FROM cohort GROUP BY cohort_month
)
SELECT a.cohort_month,
       s.cohort_size,
       a.months_since_first,
       COUNT(DISTINCT a.customer_id)                                  AS active_customers,
       ROUND(1.0 * COUNT(DISTINCT a.customer_id) / s.cohort_size, 4)  AS retention_rate
FROM activity a
JOIN sizes s ON s.cohort_month = a.cohort_month
GROUP BY a.cohort_month, s.cohort_size, a.months_since_first;

SELECT * FROM vw_cohort_retention
WHERE months_since_first IN (1, 3, 6)
ORDER BY cohort_month, months_since_first;
-- Answer: Around 25-35% of a cohort orders again in any given later month.
--         Jan 2025 looks higher because it includes customers who existed before 2025.


-- C-04  Email funnel per campaign (view)
DROP VIEW IF EXISTS vw_email_funnel;
CREATE VIEW vw_email_funnel AS
WITH ev AS (
    SELECT campaign_id,
           COUNT(DISTINCT CASE WHEN event_type = 'sent'   THEN customer_id END) AS sent,
           COUNT(DISTINCT CASE WHEN event_type = 'bounce' THEN customer_id END) AS bounced,
           COUNT(DISTINCT CASE WHEN event_type = 'open'   THEN customer_id END) AS opened,
           COUNT(DISTINCT CASE WHEN event_type = 'click'  THEN customer_id END) AS clicked,
           COUNT(DISTINCT CASE WHEN event_type = 'unsubscribe' THEN customer_id END) AS unsubscribed
    FROM stg_email_events
    GROUP BY campaign_id
),
ord AS (
    SELECT campaign_id,
           COUNT(DISTINCT order_id) AS orders,
           SUM(CASE WHEN status = 'completed' THEN net_revenue_czk ELSE 0 END) AS net_revenue_czk
    FROM fct_order_items
    WHERE channel_key = 'exponea / email' AND status <> 'cancelled'
    GROUP BY campaign_id
)
SELECT c.campaign_id,
       c.campaign_name,
       c.send_date,
       c.segment,
       ev.sent,
       ev.sent - ev.bounced                                       AS delivered,
       ev.opened,
       ev.clicked,
       COALESCE(o.orders, 0)                                      AS orders,
       ROUND(COALESCE(o.net_revenue_czk, 0))                      AS net_revenue_czk,
       ROUND(100.0 * ev.opened  / (ev.sent - ev.bounced), 1)      AS open_rate_pct,
       ROUND(100.0 * ev.clicked / ev.opened, 1)                   AS click_to_open_pct,
       ROUND(100.0 * COALESCE(o.orders, 0) / ev.clicked, 1)       AS click_to_order_pct,
       ROUND(1000.0 * COALESCE(o.net_revenue_czk, 0) / ev.sent)   AS revenue_per_1000_sent
FROM stg_email_campaigns c
JOIN ev       ON ev.campaign_id = c.campaign_id
LEFT JOIN ord o ON o.campaign_id = c.campaign_id;

SELECT * FROM vw_email_funnel ORDER BY send_date;
-- Answer: CMP-E10 'Spring Mega Sale' is broken at the click -> order step: best
--         click-to-open rate (24.7%) but only 0.4% of clickers ordered (others 10-17%).
--         Likely a broken landing page or promo code.


-- ===== MARKETING / E-SHOP ===================================================

-- M-01  ROAS and cost per order by paid campaign per quarter
SELECT d.year_quarter,
       m.campaign_id,
       ROUND(SUM(m.spend_czk))                                   AS spend_czk,
       ROUND(SUM(m.backend_revenue_czk))                         AS revenue_czk,
       ROUND(SUM(m.backend_revenue_czk) / SUM(m.spend_czk), 2)   AS roas,
       ROUND(SUM(m.spend_czk) / SUM(m.backend_orders))           AS cost_per_order_czk
FROM fct_daily_marketing m
JOIN dim_date d ON d.date = m.date
WHERE m.campaign_id IN ('CMP-G01', 'CMP-G02', 'CMP-M01', 'CMP-M02')
GROUP BY 1, 2
ORDER BY m.campaign_id, d.year_quarter;
-- Answer: CMP-M01 (Meta Prospecting) spend doubled from Q4 2025 and ROAS fell
--         from ~2.4 to ~1.2; cost per order rose from ~1,750 to ~2,700 CZK.
--         With a ~44% margin, a ROAS of 1.2 loses money. Other campaigns: ROAS 4.6-11.


-- M-02  Web conversion rate by channel group (backend web orders / GA4 sessions)
--       GA4 outage days (4-6 May 2026) excluded: no sessions recorded
SELECT ch.channel_group,
       SUM(m.sessions)                                              AS sessions,
       SUM(m.backend_web_orders)                                    AS web_orders,
       ROUND(100.0 * SUM(m.backend_web_orders) / SUM(m.sessions), 2) AS conversion_rate_pct
FROM fct_daily_marketing m
JOIN dim_channel ch ON ch.channel_key = m.channel_key
WHERE m.date NOT BETWEEN '2026-05-04' AND '2026-05-06'
GROUP BY ch.channel_group
ORDER BY conversion_rate_pct DESC;
-- Answer: Direct converts best (3.4%), Paid Social worst (1.1%).

--       ... and by device (device lives on the order and GA4 rows)
WITH s AS (
    SELECT device, SUM(sessions) AS sessions
    FROM stg_ga4_daily_traffic GROUP BY device
),
o AS (
    SELECT device, COUNT(DISTINCT order_id) AS web_orders
    FROM fct_order_items
    WHERE platform = 'web' AND status <> 'cancelled'
      AND order_date NOT BETWEEN '2026-05-04' AND '2026-05-06'
    GROUP BY device
)
SELECT s.device, s.sessions, o.web_orders,
       ROUND(100.0 * o.web_orders / s.sessions, 2) AS conversion_rate_pct
FROM s JOIN o ON o.device = s.device
ORDER BY conversion_rate_pct DESC;
-- Answer: No difference by device (~2.2% each).


-- M-03  App vs web: share of orders per quarter, AOV
SELECT d.year_quarter,
       f.platform,
       COUNT(DISTINCT CASE WHEN f.status <> 'cancelled' THEN f.order_id END) AS orders,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN f.status <> 'cancelled' THEN f.order_id END)
             / SUM(COUNT(DISTINCT CASE WHEN f.status <> 'cancelled' THEN f.order_id END)) OVER (PARTITION BY d.year_quarter), 1) AS order_share_pct,
       ROUND(SUM(CASE WHEN f.status = 'completed' THEN f.net_revenue_czk END)
             / COUNT(DISTINCT CASE WHEN f.status = 'completed' THEN f.order_id END)) AS aov_czk
FROM fct_order_items f
JOIN dim_date d ON d.date = f.order_date
GROUP BY 1, 2
ORDER BY 1, 2;
-- Answer: App share of orders grew from 32% (2025-Q1) to 46% (2026-Q2).
--         AOV is similar on both platforms.