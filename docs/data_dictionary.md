# Data Dictionary & Reporting Logic

## 1. Source tables (raw layer)

| Table | Source system | Grain | Rows | Notes |
|---|---|---|---|---|
| raw_customers | E-shop backend | 1 row per customer | 7,000 | |
| raw_products | E-shop backend | 1 row per product | 120 | |
| raw_orders | E-shop backend | 1 row per order (in theory) | 33,325 | Source of truth for orders; contains 185 duplicate rows |
| raw_order_items | E-shop backend | 1 row per order line | 56,595 | |
| raw_ga4_daily_traffic | GA4 export | date × source × medium × campaign × device | 8,193 | **Web only**, no app traffic |
| raw_email_campaigns | Exponea | 1 row per campaign | 12 | |
| raw_email_events | Exponea | 1 row per event | 39,077 | sent / open / click / bounce / unsubscribe |
| raw_ad_spend | Google Ads, Meta Ads | date × campaign | 2,184 | 4 paid campaigns |

### Key columns

| Column | Table | Meaning |
|---|---|---|
| order_ts | orders | Timestamp when the order was placed |
| status | orders | completed / cancelled / returned |
| platform | orders | web / app |
| channel_key | stg/fct tables | `source / medium`, e.g. `google / cpc`; joins orders, GA4 and ad spend |
| campaign_id | several | Joins orders, ad spend, email campaigns and GA4. `(not set)` = no campaign |
| unit_price_czk | order_items | Price charged per unit **before** discount (VAT included) |
| discount_czk | order_items | Total discount on the line (not per unit) |
| net_revenue_czk | fct_order_items | quantity × unit price − discount |
| cost_czk | fct_order_items | quantity × product unit cost |
| margin_czk | fct_order_items | net revenue − cost |
| is_first_order | fct_order_items | 1 if this is the customer's first non-cancelled order |
| shipping_fee_czk | orders | Shipping charged to the customer (excluded from revenue) |
| sessions | fct_daily_marketing | GA4 sessions (web only) |
| backend_orders / backend_web_orders | fct_daily_marketing | Non-cancelled orders from the backend (all platforms / web only) |
| backend_revenue_czk | fct_daily_marketing | Net revenue of completed orders from the backend |
| spend_czk | fct_daily_marketing | Ad spend (paid campaigns only) |

## 2. KPI definitions

| KPI | Formula | Decision and reason |
|---|---|---|
| Net revenue | Σ (quantity × unit price − discount), **completed** orders | Cancelled and returned orders excluded (money not kept). Shipping excluded (not product revenue). VAT included as in the source; stated on the dashboard. |
| Orders | Count of distinct orders with status ≠ cancelled | Returned orders still count as orders placed (demand); test orders excluded. |
| AOV | Net revenue ÷ completed orders | Numerator and denominator use the same orders. |
| Margin % | (Net revenue − cost) ÷ net revenue | Based on net revenue, so discounts reduce margin. |
| Return rate | Returned ÷ (completed + returned) | Cancelled orders never shipped, so they can't be returned. |
| New customer | Customer's first-ever non-cancelled order | "Ever" within the data; customers from before 2025 appear as new in Jan 2025 (noted on the dashboard). |
| Repeat purchase rate | % of new customers with a 2nd order ≤ 90 days after the first | Only customers whose first order was ≥ 90 days before the data end, so everyone had the full window. |
| Conversion rate | Backend web orders ÷ GA4 sessions | GA4 misses 3–14% of purchases, so backend orders are used. GA4 outage days excluded. |
| ROAS | Backend net revenue ÷ ad spend | Backend, not GA4, so it matches the revenue figures elsewhere. |
| Email open rate / CTOR | Unique opens ÷ delivered; unique clicks ÷ unique opens | Unique customers, so repeated opens don't inflate the rates. |

## 3. Cleaning rules

| Rule ID | Table | Problem | Rule applied | Rows affected |
|---|---|---|---|---|
| C-01 | products | Missing category | Derived from brand (each brand has one category) | 4 |
| C-02 | customers | City spelled several ways | Standardised to Praha / Brno | 292 |
| C-03 | customers | Missing region | Derived from the cleaned city | 210 |
| C-04 | orders | Czech timestamps `DD.MM.YYYY HH:MM` | Converted to ISO `YYYY-MM-DD HH:MM:SS` | 833 (821 after de-duplication) |
| C-05 | orders | 12 spellings of 3 status values | `LOWER(TRIM(status))` | 1,999 |
| C-06 | orders | Duplicate rows | One row per order_id (`ROW_NUMBER`) | 185 removed |
| C-07 | orders | QA test orders (customer 99999, code QA_TEST) | Flagged `is_test_order = 1`, excluded from reporting | 14 |
| C-08 | order_items | Negative unit price (sign error) | `ABS()` | 38 |
| C-09 | order_items | Quantity = 0 | Flagged `is_valid = 0`, excluded | 22 |
| C-10 | order_items | Lines with no matching order | Flagged `is_orphan = 1`, excluded; reported to DWH | 319 (≈731k CZK) |
| C-11 | order_items | Lines of test orders | Excluded via `is_test_order` | 14 |

Result: **56,241** of 56,595 order lines go into the reporting layer.

## 4. Reporting layer

| Table | Grain | Built from | Used on dashboard page |
|---|---|---|---|
| fct_order_items | order line | stg_orders, stg_order_items | Overview, Sales, Customers, Marketing |
| fct_daily_marketing | date × channel × campaign | stg_ga4_daily_traffic, stg_ad_spend, stg_orders | Marketing |
| dim_date | day | calendar (recursive CTE) | All |
| dim_customer | customer | stg_customers, stg_orders | Customers |
| dim_product | product | stg_products | Sales |
| dim_channel | source / medium | all sources | Marketing |
| vw_cohort_retention | cohort month × months since first order | fct_order_items | Customers |
| vw_email_funnel | email campaign | stg_email_events, fct_order_items | Customers |
| vw_daily_completeness | day | fct_order_items, stg_ga4_daily_traffic | Overview (warning), Data Quality |
| vw_dq_scorecard | DQ check | raw tables | Data Quality |