# Data Quality Log

All issues found by `sql/02_data_quality_checks.sql` and `sql/06_anomaly_detection.sql`.

| ID | Table | Issue | How found | Rows affected | Business impact | Decision | Owner |
|---|---|---|---|---|---|---|---|
| DQ-01 | raw_orders | Duplicate order rows (double-loaded batch); copies differ only in formatting | COUNT vs COUNT(DISTINCT order_id) | 185 | Orders and revenue overstated | Keep one row per order_id | DWH team |
| DQ-02 | raw_order_items / raw_orders | **All app orders 9–15 Mar 2026 missing**; their 319 lines were loaded | Orphan lines + platform split of the order_id range | 319 lines / 184 orders / ≈731k CZK | Week looks like a 40% demand drop | Excluded; week flagged on dashboard; reload requested | DWH team |
| DQ-03 | raw_orders | Internal QA test orders (customer 99999, QA_TEST) | Orders with no matching customer | 14 | Fake revenue (≈10M CZK from 99,999-CZK prices) | Flagged and excluded | E-shop team |
| DQ-04 | raw_orders | Status written 12 different ways | DISTINCT status | 1,999 | Filters on "completed" miss ~6% of orders | LOWER(TRIM()) | DWH team |
| DQ-05 | raw_orders | Timestamps in Czech format from legacy checkout | NOT LIKE ISO pattern | 833 | Orders silently drop out of date filters | Converted to ISO | DWH team |
| DQ-06a | raw_order_items | Negative unit prices; absolute value = list price | price ≤ 0 + comparison with list price | 38 | Revenue understated | ABS() | DWH team |
| DQ-06b | raw_order_items | Quantity = 0 | quantity ≤ 0 | 22 | Lines with no value | Excluded | DWH team |
| DQ-07 | raw_order_items | Prices of 1 or 99,999 CZK | Price vs 0.5×–2× list price | 14 | Same as DQ-03 | Excluded with test orders | — |
| DQ-08a | raw_customers | Missing region | NULL check | 210 (3.0%) | Regional reports incomplete | Derived from city | CRM team |
| DQ-08b | raw_products | Missing category | NULL check | 4 | Revenue in "Unknown" category | Derived from brand | E-shop team |
| DQ-09 | raw_customers | Praha / Brno spelled several ways | DISTINCT city | 292 | City split into several rows | Standardised | CRM team |
| DQ-10 | raw_ga4_daily_traffic | No GA4 data 4–6 May 2026 (tracking outage) | Calendar vs GA4 dates | 3 days | Conversion rate would be wrong | Days excluded from conversion; flagged | Web analytics |
| DQ-11 | GA4 vs backend | GA4 revenue 3–14% below backend every day | Daily reconciliation | All days | Not an error: consent and ad blockers | Backend = source of truth | — |

## Recommendations to the DWH team
1. Add a **unique constraint on `order_id`** in the orders table to stop double-loaded batches.
2. Add an **ingestion completeness check per platform per day** (alert when app or web orders are 0 or < 50% of the 4-week same-weekday average).
3. Load order headers and order lines in **one transaction**, so lines can never exist without their order.
4. Store **status as a controlled list** (enum / lookup table) and **timestamps as a datetime type**, not text.
5. Exclude internal **QA accounts** at the source, or flag them with an `is_test` column.