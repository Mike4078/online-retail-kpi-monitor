# Business Requirements

**Company:** NovaShop.cz (fictional Czech online retailer: electronics, home, beauty, sports, toys, fashion)
**Sold through:** web shop + mobile app
**Data sources:** e-shop backend database, GA4 (web), Exponea (email), Google Ads + Meta Ads
**Period:** January 2025 – June 2026

> In a real role you would collect these in short meetings with each business unit.
> Write them up the same way here: who asked, what they need, and how they'll use it.

---

## Stakeholder 1: Head of Sales
**Context:** Revenue is growing but margin feels flat. Management wants to know where the money comes from.

| ID | Question | How it will be used | Frequency |
|---|---|---|---|
| S-01 | How are revenue, orders and AOV developing month by month? | Monthly management report | Monthly |
| S-02 | Which categories are growing or shrinking, and what's their margin? | Category budget planning | Quarterly |
| S-03 | Which products drive our margin, and has that changed? | Assortment decisions | Quarterly |
| S-04 | Are returns a problem anywhere? | Supplier conversations | Monthly |
| S-05 | Was Black Friday 2025 profitable, or did we just discount? | Plan Black Friday 2026 | One-off |

## Stakeholder 2: CRM & Email Lead
**Context:** Uses Exponea for newsletters. Feels some campaigns "aren't working" but can't prove it.

| ID | Question | How it will be used | Frequency |
|---|---|---|---|
| C-01 | How much revenue comes from new vs. returning customers? | Retention strategy | Monthly |
| C-02 | Which channels bring customers who come back? | Acquisition budget | Quarterly |
| C-03 | How well do we retain customers over time (cohorts)? | Loyalty programme business case | Quarterly |
| C-04 | Which email campaigns work, and where do the others fail? | Campaign planning | Per campaign |

## Stakeholder 3: E-commerce Manager
**Context:** Owns the web shop, app and paid marketing budget. Doesn't trust GA4 numbers fully.

| ID | Question | How it will be used | Frequency |
|---|---|---|---|
| M-01 | Which paid campaigns pay back their spend (ROAS)? | Budget reallocation | Weekly |
| M-02 | What's our web conversion rate by channel and device? | UX / landing page priorities | Weekly |
| M-03 | How is the app performing vs. web? | App investment decision | Quarterly |

## Cross-cutting requirements (from all stakeholders)
- "One version of the truth": revenue must mean the same thing on every page → see KPI definitions in `data_dictionary.md`
- Backend data is the **source of truth** for orders and revenue; GA4 is used for traffic only
- The dashboard must show **when data is incomplete**, so nobody makes decisions based on a broken day
- Numbers must be understandable by non-analysts → plain-English tooltips and a definitions page
