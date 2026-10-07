# Power BI Dashboard Spec

**Load data:** run `python python/export_for_powerbi.py`, then in Power BI Desktop use
**Get data → Folder** (point to `/exports`) or **Text/CSV** for each file.

**Model:** star schema. Relationships (single direction, many-to-one):
- fct_order_items[order_date] → dim_date[date]
- fct_order_items[customer_id] → dim_customer[customer_id]
- fct_order_items[product_id] → dim_product[product_id]
- fct_order_items[channel_key] → dim_channel[channel_key]
- fct_daily_marketing[date] → dim_date[date]
- fct_daily_marketing[channel_key] → dim_channel[channel_key]

Mark `dim_date` as the date table. Save the file as `powerbi/NovaShop_KPI_Monitor.pbix`.

## DAX measures to build (put them in a dedicated `_Measures` table)
| Measure | Notes |
|---|---|
| Net Revenue | Must follow your KPI definition (status filter!) |
| Orders | DISTINCTCOUNT(order_id) with the same status logic |
| AOV | DIVIDE([Net Revenue], [Orders]) |
| Margin % | |
| Return Rate % | |
| Net Revenue PY / MoM % | Time intelligence: SAMEPERIODLASTYEAR / DATEADD |
| New Customer Revenue % | Using is_first_order |
| ROAS | DIVIDE(backend revenue, spend) |
| Conversion Rate % | Web only |
| Data Completeness Flag | Shows a warning when a day has a known data issue |

## Pages
1. **Overview**: KPI cards (Revenue, Orders, AOV, Margin %) with MoM %, monthly revenue trend, category split, slicers for date / platform / category
2. **Sales & Products**: category share over time, top products table with rank change, return rate by brand (conditional formatting)
3. **Customers & CRM**: new vs. returning, repeat rate by acquisition channel, cohort heatmap (matrix), email funnel per campaign
4. **Marketing**: ROAS by campaign over time, conversion rate by channel group and device, spend vs. revenue
5. **Data Quality**: DQ scorecard from 02, daily completeness check (GA4 vs. backend), list of known issues
6. **Definitions**: KPI definitions in plain English (copied from data_dictionary.md)

## Design rules
- Max 6–8 visuals per page; titles that state the insight ("App share grew from 32% to 46%"), not just "App share"
- Consistent colours per category / channel on every page
- Tooltips explaining each KPI
- Take screenshots of each page for the README (`powerbi/screenshots/`)
