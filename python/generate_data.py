"""
Synthetic data generator for the Online Retail KPI Monitor project.

Creates realistic (but fully fictional) raw exports for an online retailer
"NovaShop.cz" covering Jan 2025 - Jun 2026:

  backend (e-shop database)   -> customers, products, orders, order_items
  GA4-style export            -> ga4_daily_traffic
  Exponea-style export        -> email_campaigns, email_events
  marketing spend export      -> ad_spend

Raw data is intentionally NOT clean - just like real source systems.
Run:  python python/generate_data.py
Output: data/raw/*.csv
"""
from pathlib import Path
from datetime import date, datetime, timedelta
import numpy as np
import pandas as pd

SEED = 42
rng = np.random.default_rng(SEED)
OUT = Path(__file__).resolve().parents[1] / "data" / "raw"
OUT.mkdir(parents=True, exist_ok=True)

START, END = date(2025, 1, 1), date(2026, 6, 30)
DAYS = pd.date_range(START, END, freq="D")

# ----------------------------------------------------------------------------
# 1. PRODUCTS
# ----------------------------------------------------------------------------
CATEGORIES = {
    #  category        n   median price  brands
    "Electronics":    (22, 3200, ["Voltix", "Sonara", "PixelCore", "Ampero"]),
    "Home & Kitchen": (24, 900,  ["Domka", "CasaLine", "Kuchyňka"]),
    "Beauty":         (20, 450,  ["Glowé", "PureLab", "Rosa Natura"]),
    "Sports":         (18, 1100, ["Trailo", "FitMotion", "Alpinka"]),
    "Toys":           (16, 650,  ["Hrátky", "BrickWay", "Kiddo"]),
    "Fashion":        (20, 1300, ["NordWear", "Urbanic", "Linea"]),
}
NOUNS = {
    "Electronics": ["Wireless Earbuds", "Bluetooth Speaker", "Smart Watch", "Power Bank", "USB-C Hub",
                    "Gaming Mouse", "Mechanical Keyboard", "4K Webcam", "Noise-Cancelling Headphones", "Tablet Stand", "Smart Plug"],
    "Home & Kitchen": ["Chef Knife", "Coffee Grinder", "Cast Iron Pan", "Storage Box Set", "Bed Linen Set",
                       "Electric Kettle", "Table Lamp", "Blender", "Towel Set", "Food Containers", "Cutting Board", "Scented Candle"],
    "Beauty": ["Face Serum", "Night Cream", "Shampoo", "Body Lotion", "Lip Balm", "Sunscreen SPF50",
               "Hair Mask", "Cleansing Gel", "Eye Cream", "Hand Cream"],
    "Sports": ["Yoga Mat", "Running Shoes", "Dumbbell Set", "Hiking Backpack", "Water Bottle",
               "Resistance Bands", "Cycling Gloves", "Sports Watch", "Foam Roller"],
    "Toys": ["Building Blocks", "Puzzle 1000pc", "Plush Bear", "Board Game", "RC Car", "Art Set", "Train Set", "Doll House"],
    "Fashion": ["Winter Jacket", "Wool Sweater", "Denim Jeans", "Sneakers", "Leather Belt",
                "Rain Coat", "Cotton T-Shirt", "Scarf", "Chino Trousers", "Hoodie"],
}
rows, pid = [], 1001
for cat, (n, med, brands) in CATEGORIES.items():
    for i in range(n):
        noun = NOUNS[cat][i % len(NOUNS[cat])]
        brand = brands[i % len(brands)]
        price = round(float(rng.lognormal(np.log(med), 0.45)), -1) - 1  # e.g. 1299
        cost = round(price * rng.uniform(0.45, 0.68), 2)
        rows.append(dict(product_id=pid, product_name=f"{brand} {noun}", category=cat, brand=brand,
                         list_price_czk=price, unit_cost_czk=cost,
                         launch_date=str(START - timedelta(days=int(rng.integers(30, 900))))))
        pid += 1
products = pd.DataFrame(rows)
# a few newer products launched during the period
new_idx = rng.choice(products.index, 8, replace=False)
products.loc[new_idx, "launch_date"] = [str(START + timedelta(days=int(d))) for d in rng.integers(60, 420, 8)]

# ----------------------------------------------------------------------------
# 2. CUSTOMERS
# ----------------------------------------------------------------------------
REGIONS = {  # region: (weight, main city)
    "Hlavní město Praha": (0.20, "Praha"), "Středočeský kraj": (0.13, "Kladno"),
    "Jihomoravský kraj": (0.12, "Brno"), "Moravskoslezský kraj": (0.11, "Ostrava"),
    "Ústecký kraj": (0.07, "Ústí nad Labem"), "Jihočeský kraj": (0.06, "České Budějovice"),
    "Olomoucký kraj": (0.06, "Olomouc"), "Plzeňský kraj": (0.06, "Plzeň"),
    "Zlínský kraj": (0.05, "Zlín"), "Královéhradecký kraj": (0.05, "Hradec Králové"),
    "Pardubický kraj": (0.04, "Pardubice"), "Vysočina": (0.02, "Jihlava"),
    "Liberecký kraj": (0.02, "Liberec"), "Karlovarský kraj": (0.01, "Karlovy Vary"),
}
reg_names = list(REGIONS)
reg_w = np.array([REGIONS[r][0] for r in reg_names]); reg_w /= reg_w.sum()

N_CUST = 7000
# signup dates: ~35% existing before 2025, rest spread across the period (growing)
pre = pd.to_datetime("2023-01-01") + pd.to_timedelta(rng.integers(0, 730, int(N_CUST * 0.35)), "D")
t = rng.power(1.4, N_CUST - len(pre))  # skew towards later dates = growth
post = pd.to_datetime(START) + pd.to_timedelta((t * (len(DAYS) - 10)).astype(int), "D")
signup = np.sort(np.concatenate([pre.values, post.values]))

cust_region = rng.choice(reg_names, N_CUST, p=reg_w)
customers = pd.DataFrame({
    "customer_id": np.arange(50001, 50001 + N_CUST),
    "signup_date": pd.to_datetime(signup).strftime("%Y-%m-%d"),
    "region": cust_region,
    "city": [REGIONS[r][1] for r in cust_region],
    "age_band": rng.choice(["18-24", "25-34", "35-44", "45-54", "55+"], N_CUST, p=[.14, .31, .26, .17, .12]),
    "email_opt_in": rng.choice([1, 0], N_CUST, p=[.64, .36]),
    "acquisition_channel": rng.choice(["organic", "google_cpc", "meta_paid_social", "referral", "email"],
                                      N_CUST, p=[.34, .30, .20, .10, .06]),
})
# customer "loyalty" propensity -> drives repeat purchases
cust_w = rng.lognormal(0, 1.0, N_CUST)
cust_signup = pd.to_datetime(customers["signup_date"]).values

# ----------------------------------------------------------------------------
# 3. MARKETING: campaigns, ad spend
# ----------------------------------------------------------------------------
paid_campaigns = pd.DataFrame([
    ("CMP-G01", "Google Search - Brand",       "google", "cpc"),
    ("CMP-G02", "Google Shopping - All",        "google", "cpc"),
    ("CMP-M01", "Meta - Prospecting Broad",     "meta",   "paid_social"),
    ("CMP-M02", "Meta - Retargeting",           "meta",   "paid_social"),
], columns=["campaign_id", "campaign_name", "source", "medium"])

EMAIL_CAMPAIGNS = [
    # id,        name,                          send date,    segment,            theme,          broken landing page?
    ("CMP-E01", "New Year Deals",               "2025-01-08", "all_opted_in",     "discount",     False),
    ("CMP-E02", "Valentine Gift Guide",         "2025-02-06", "all_opted_in",     "gift_guide",   False),
    ("CMP-E03", "Spring Beauty Picks",          "2025-03-20", "beauty_buyers",    "category",     False),
    ("CMP-E04", "Summer Sports Sale",           "2025-06-12", "all_opted_in",     "discount",     False),
    ("CMP-E05", "Back to School",               "2025-08-21", "all_opted_in",     "category",     False),
    ("CMP-E06", "Autumn Home Refresh",          "2025-10-02", "home_buyers",      "category",     False),
    ("CMP-E07", "Black Friday Early Access",    "2025-11-24", "all_opted_in",     "discount",     False),
    ("CMP-E08", "Christmas Gift Guide",         "2025-12-04", "all_opted_in",     "gift_guide",   False),
    ("CMP-E09", "Winter Clearance",             "2026-01-15", "all_opted_in",     "discount",     False),
    ("CMP-E10", "Spring Mega Sale",             "2026-04-09", "all_opted_in",     "discount",     True),   # planted
    ("CMP-E11", "We Miss You - Winback",        "2026-05-14", "lapsed_customers", "winback",      False),
    ("CMP-E12", "Summer Essentials",            "2026-06-11", "all_opted_in",     "category",     False),
]
email_campaigns = pd.DataFrame([e[:5] for e in EMAIL_CAMPAIGNS],
                               columns=["campaign_id", "campaign_name", "send_date", "segment", "theme"])

# ----------------------------------------------------------------------------
# 4. DAILY DEMAND MODEL
# ----------------------------------------------------------------------------
def demand_factor(d: pd.Timestamp) -> float:
    f = 1.0
    f *= {0: 1.05, 1: 1.0, 2: 1.0, 3: 1.02, 4: 0.95, 5: 0.85, 6: 1.10}[d.weekday()]
    f *= {1: 0.85, 2: 0.88, 3: 0.95, 4: 0.97, 5: 0.98, 6: 0.92, 7: 0.88, 8: 0.92,
          9: 1.0, 10: 1.08, 11: 1.35, 12: 1.45}[d.month]
    if d.month == 11 and 24 <= d.day <= 30:      # Black Friday week
        f *= 2.1
    if d.month == 12 and d.day > 20:             # after shipping cut-off
        f *= 0.55
    growth = 1 + 0.35 * ((d - pd.Timestamp(START)).days / len(DAYS))
    return f * growth

def category_weights(d: pd.Timestamp) -> np.ndarray:
    p = (d - pd.Timestamp(START)).days / len(DAYS)  # 0..1
    w = {"Electronics": 0.24 - 0.14 * p,   # declining share (planted trend)
         "Home & Kitchen": 0.20, "Beauty": 0.12 + 0.12 * p,  # growing share
         "Sports": 0.14 + (0.05 if d.month in (5, 6, 7) else 0), "Toys": 0.10 + (0.08 if d.month in (11, 12) else 0),
         "Fashion": 0.16 + (0.04 if d.month in (10, 11, 12, 1) else 0)}
    a = np.array([w[c] for c in CATEGORIES]); return a / a.sum()

cat_names = list(CATEGORIES)
HOUR_P = np.array([1, .5, .3, .2, .2, .4, 1, 2, 3, 4, 4.5, 5, 5.5, 5, 4.5, 4.5, 5, 5.5, 6.5, 7.5, 8, 7, 5, 2.5])
HOUR_P = HOUR_P / HOUR_P.sum()
prods_by_cat = {c: products[products.category == c].to_dict('records') for c in cat_names}

BASE_ORDERS_PER_DAY = 52
orders, items = [], []
oid, iid = 900001, 1

def pick_source(d):
    """Traffic source/medium/campaign for an order."""
    r = rng.random()
    if r < 0.30: return ("google", "organic", None)
    if r < 0.40: return ("(direct)", "(none)", None)
    if r < 0.62: return ("google", "cpc", rng.choice(["CMP-G01", "CMP-G02"], p=[.45, .55]))
    if r < 0.74: return ("meta", "paid_social", rng.choice(["CMP-M01", "CMP-M02"], p=[.5, .5]))
    if r < 0.82: return ("heureka", "referral", None)
    return ("newsletter", "email", None)

def add_order(ts, cust_id, platform, source, medium, campaign, cat_w):
    global oid, iid
    n_items = rng.choice([1, 2, 3, 4], p=[.55, .27, .12, .06])
    disc_code = None
    if ts.month == 11 and 24 <= ts.day <= 30 and rng.random() < 0.55: disc_code = "BLACKFRIDAY25"
    elif rng.random() < 0.09: disc_code = rng.choice(["WELCOME10", "SPRING15", "VIP20", "FREESHIP"])
    has_fashion_nord = False
    first = len(items)
    for _ in range(n_items):
        cat = rng.choice(cat_names, p=cat_w)
        live = [x for x in prods_by_cat[cat] if x["launch_date"] <= str(ts.date())]
        p = live[int(rng.integers(len(live)))]
        qty = int(rng.choice([1, 1, 1, 1, 2, 2, 3]))
        price = p['list_price_czk']
        # Electronics price increase from Sep 2025 (+8%)
        if p['category'] == "Electronics" and ts >= pd.Timestamp("2025-09-01"):
            price = round(price * 1.08, -1) - 1
        disc = 0.0
        if disc_code in ("BLACKFRIDAY25",): disc = round(price * qty * 0.25, 2)
        elif disc_code in ("WELCOME10",): disc = round(price * qty * 0.10, 2)
        elif disc_code in ("SPRING15",): disc = round(price * qty * 0.15, 2)
        elif disc_code in ("VIP20",): disc = round(price * qty * 0.20, 2)
        if p['brand'] == "NordWear": has_fashion_nord = True
        items.append(dict(order_item_id=iid, order_id=oid, product_id=int(p['product_id']), quantity=qty,
                          unit_price_czk=price, discount_czk=disc, _cat=p['category'], _brand=p['brand']))
        iid += 1
    # status: returns higher for Fashion, NordWear much higher after supplier change Feb 2026
    my_items = items[first:]
    r_rate = 0.05
    if any(it["_cat"] == "Fashion" for it in my_items): r_rate = 0.14
    if has_fashion_nord and ts >= pd.Timestamp("2026-02-01"): r_rate = 0.34
    status = rng.choice(["completed", "cancelled", "returned"], p=[1 - 0.045 - r_rate, 0.045, r_rate])
    subtotal = sum(it["unit_price_czk"] * it["quantity"] - it["discount_czk"] for it in my_items)
    ship = 0 if (subtotal >= 1500 or disc_code == "FREESHIP") else 89
    orders.append(dict(order_id=oid, customer_id=int(cust_id), order_ts=ts.strftime("%Y-%m-%d %H:%M:%S"),
                       platform=platform, device="mobile" if platform == "app" else rng.choice(["desktop", "mobile", "tablet"], p=[.45, .48, .07]),
                       traffic_source=source, traffic_medium=medium, campaign_id=campaign,
                       status=status, discount_code=disc_code, shipping_fee_czk=ship))
    oid += 1

email_open_click = []  # collected for email events
for d in DAYS:
    n = rng.poisson(BASE_ORDERS_PER_DAY * demand_factor(d))
    elig = int(np.searchsorted(cust_signup, np.datetime64(d.date()), side="right"))
    w = cust_w[:elig] / cust_w[:elig].sum()
    custs = rng.choice(customers.customer_id.values[:elig], n, p=w)
    cat_w = category_weights(d)
    p_app = 0.32 + 0.14 * ((d - pd.Timestamp(START)).days / len(DAYS))
    for c in custs:
        hour = int(rng.choice(24, p=HOUR_P))
        ts = d + pd.Timedelta(hours=hour, minutes=int(rng.integers(60)), seconds=int(rng.integers(60)))
        platform = "app" if rng.random() < p_app else "web"
        s, m, cmp = pick_source(d)
        add_order(ts, c, platform, s, m, cmp, cat_w)

# ----------------------------------------------------------------------------
# 5. EMAIL CAMPAIGNS (Exponea-style events) + attributed orders
# ----------------------------------------------------------------------------
cust_df = customers.copy()
cust_df["signup_dt"] = pd.to_datetime(cust_df.signup_date)
o_tmp = pd.DataFrame(orders); it_tmp = pd.DataFrame(items)
o_tmp["order_dt"] = pd.to_datetime(o_tmp.order_ts)
cat_buyers = it_tmp.merge(o_tmp[["order_id", "customer_id"]], on="order_id")

events, evid = [], 1
for cid, name, send_date, segment, theme, broken in EMAIL_CAMPAIGNS:
    sd = pd.Timestamp(send_date) + pd.Timedelta(hours=9, minutes=30)
    base = cust_df[(cust_df.email_opt_in == 1) & (cust_df.signup_dt < sd)]
    if segment == "beauty_buyers":
        base = base[base.customer_id.isin(cat_buyers[cat_buyers._cat == "Beauty"].customer_id)]
    elif segment == "home_buyers":
        base = base[base.customer_id.isin(cat_buyers[cat_buyers._cat == "Home & Kitchen"].customer_id)]
    elif segment == "lapsed_customers":
        last = o_tmp[o_tmp.order_dt < sd].groupby("customer_id").order_dt.max()
        lapsed = last[last < sd - pd.Timedelta(days=150)].index
        base = base[base.customer_id.isin(lapsed)]
    recips = base.customer_id.values
    open_r = {"discount": .27, "gift_guide": .24, "category": .31, "winback": .19}[theme]
    click_r = .26 if broken else {"discount": .14, "gift_guide": .12, "category": .16, "winback": .10}[theme]  # share of openers
    conv_r = .004 if broken else {"discount": .16, "gift_guide": .13, "category": .15, "winback": .09}[theme]  # share of clickers
    for c in recips:
        events.append((evid, cid, int(c), "sent", sd.strftime("%Y-%m-%d %H:%M:%S"))); evid += 1
        if rng.random() < .012:
            events.append((evid, cid, int(c), "bounce", (sd + pd.Timedelta(minutes=2)).strftime("%Y-%m-%d %H:%M:%S"))); evid += 1
            continue
        if rng.random() < open_r:
            ot = sd + pd.Timedelta(minutes=int(rng.exponential(300)))
            events.append((evid, cid, int(c), "open", ot.strftime("%Y-%m-%d %H:%M:%S"))); evid += 1
            if rng.random() < click_r:
                ct = ot + pd.Timedelta(minutes=int(rng.integers(1, 20)))
                events.append((evid, cid, int(c), "click", ct.strftime("%Y-%m-%d %H:%M:%S"))); evid += 1
                if rng.random() < conv_r:
                    ts = ct + pd.Timedelta(minutes=int(rng.integers(5, 2880)))
                    if ts.date() <= END:
                        add_order(ts, c, "web", "exponea", "email", cid, category_weights(ts))
            if rng.random() < .003:
                events.append((evid, cid, int(c), "unsubscribe", (ot + pd.Timedelta(minutes=3)).strftime("%Y-%m-%d %H:%M:%S"))); evid += 1
email_events = pd.DataFrame(events, columns=["event_id", "campaign_id", "customer_id", "event_type", "event_ts"])

orders = pd.DataFrame(orders).sort_values("order_ts").reset_index(drop=True)
items = pd.DataFrame(items)

# ----------------------------------------------------------------------------
# 6. AD SPEND (daily, paid campaigns)
# ----------------------------------------------------------------------------
spend_rows = []
spend_base = {"CMP-G01": 1900, "CMP-G02": 4200, "CMP-M01": 5200, "CMP-M02": 1600}
for d in DAYS:
    f = demand_factor(d) ** 0.8
    for c, b in spend_base.items():
        s = b * f * rng.uniform(0.85, 1.15)
        if c == "CMP-M01" and d >= pd.Timestamp("2025-10-01"): s *= 1.6   # budget scaled up, ROAS falls
        spend_rows.append((str(d.date()), c, round(s, 2), int(s / rng.uniform(4.5, 9))))
ad_spend = pd.DataFrame(spend_rows, columns=["date", "campaign_id", "spend_czk", "clicks"])
ad_spend = ad_spend.merge(paid_campaigns, on="campaign_id")[
    ["date", "source", "medium", "campaign_id", "campaign_name", "spend_czk", "clicks"]]

# ----------------------------------------------------------------------------
# 7. GA4 DAILY TRAFFIC (web only; app tracked separately - not in this export)
# ----------------------------------------------------------------------------
web = orders[orders.platform == "web"].copy()
web["date"] = web.order_ts.str[:10]
it_val = items.assign(v=items.unit_price_czk * items.quantity - items.discount_czk).groupby("order_id").v.sum()
web["rev"] = web.order_id.map(it_val).fillna(0)
web["campaign_id"] = web.campaign_id.fillna("(not set)")
g = web.groupby(["date", "traffic_source", "traffic_medium", "campaign_id", "device"]).agg(
    purchases=("order_id", "count"), purchase_revenue=("rev", "sum")).reset_index()
conv = {"organic": .028, "(none)": .035, "cpc": .022, "paid_social": .011, "referral": .03, "email": .03}
g["sessions"] = [max(p, int(p / conv[m] * rng.uniform(.85, 1.15))) for p, m in zip(g.purchases, g.traffic_medium)]
g["engaged_sessions"] = (g.sessions * rng.uniform(.5, .66, len(g))).astype(int)
# GA4 misses some purchases (ad blockers / consent) -> ~8% under-reporting, realistic reconciliation gap
g["purchases"] = (g.purchases * rng.uniform(.86, .97, len(g))).round().astype(int)
g["purchase_revenue"] = (g.purchase_revenue * rng.uniform(.86, .97, len(g))).round(2)
# email clicks from broken campaign create sessions with no purchases
ev_clicks = email_events[email_events.event_type == "click"].copy()
ev_clicks["date"] = ev_clicks.event_ts.str[:10]
ec = ev_clicks.groupby(["date", "campaign_id"]).size().reset_index(name="clicks")
extra = pd.DataFrame({"date": ec.date, "traffic_source": "exponea", "traffic_medium": "email",
                      "campaign_id": ec.campaign_id, "device": "mobile", "sessions": ec.clicks,
                      "engaged_sessions": (ec.clicks * .4).astype(int), "purchases": 0, "purchase_revenue": 0.0})
g = pd.concat([g, extra]).groupby(["date", "traffic_source", "traffic_medium", "campaign_id", "device"], as_index=False).sum()
g = g.rename(columns={"traffic_source": "session_source", "traffic_medium": "session_medium",
                      "campaign_id": "session_campaign_id"})
ga4 = g[["date", "session_source", "session_medium", "session_campaign_id", "device",
         "sessions", "engaged_sessions", "purchases", "purchase_revenue"]]

# ============================================================================
# 8. PLANT DATA QUALITY ISSUES  (see PRIVATE_answer_key.md - do not publish)
# ============================================================================
# (a) Ingestion failure: app orders missing 9-15 Mar 2026, but their items were loaded
gap = (orders.platform == "app") & (orders.order_ts >= "2026-03-09") & (orders.order_ts < "2026-03-16")
orders = orders[~gap]
# (b) Duplicate order rows (double-loaded batch)
dups = orders.sample(185, random_state=SEED)
orders = pd.concat([orders, dups]).sort_values("order_ts").reset_index(drop=True)
# (c) Inconsistent status values
idx = orders.sample(frac=.06, random_state=1).index
orders.loc[idx, "status"] = orders.loc[idx, "status"].map(
    lambda s: rng.choice([s.upper(), s.capitalize(), s + " "]))
# (d) Some timestamps in Czech format DD.MM.YYYY HH:MM (from a legacy checkout)
idx = orders.sample(frac=.025, random_state=2).index
orders.loc[idx, "order_ts"] = pd.to_datetime(orders.loc[idx, "order_ts"]).dt.strftime("%d.%m.%Y %H:%M")
# (e) Test orders from an internal QA account not in customers table
for k in range(14):
    ts = pd.Timestamp("2025-03-01") + pd.Timedelta(days=int(rng.integers(0, 480)), hours=10)
    orders.loc[len(orders)] = dict(order_id=990000 + k, customer_id=99999, order_ts=ts.strftime("%Y-%m-%d %H:%M:%S"),
                                   platform="web", device="desktop", traffic_source="(direct)", traffic_medium="(none)",
                                   campaign_id=None, status="completed", discount_code="QA_TEST", shipping_fee_czk=0)
    items.loc[len(items)] = dict(order_item_id=iid, order_id=990000 + k, product_id=int(rng.choice(products.product_id)),
                                 quantity=int(rng.choice([1, 50])), unit_price_czk=float(rng.choice([1, 99999])),
                                 discount_czk=0, _cat=None, _brand=None); iid += 1
# (f) Bad item values
items.loc[items.sample(38, random_state=3).index, "unit_price_czk"] *= -1
items.loc[items.sample(22, random_state=4).index, "quantity"] = 0
# (g) Messy customer attributes
idx = customers.sample(frac=.03, random_state=5).index; customers.loc[idx, "region"] = None
praha = customers[customers.city == "Praha"].sample(frac=.15, random_state=6).index
customers.loc[praha, "city"] = rng.choice(["praha", "Prague", "Praha ", "PRAHA", "Praha 5"], len(praha))
brno = customers[customers.city == "Brno"].sample(frac=.1, random_state=7).index
customers.loc[brno, "city"] = rng.choice(["brno", "Brno-střed", "BRNO"], len(brno))
# (h) Products missing category
products.loc[products.sample(4, random_state=8).index, "category"] = None
# (i) GA4 tracking outage 4-6 May 2026 (no web traffic recorded)
ga4 = ga4[~ga4.date.between("2026-05-04", "2026-05-06")]

# ----------------------------------------------------------------------------
# 9. WRITE
# ----------------------------------------------------------------------------
items = items.drop(columns=["_cat", "_brand"])
items["quantity"] = items["quantity"].astype(int)
outputs = {
    "customers": customers, "products": products, "orders": orders, "order_items": items,
    "ga4_daily_traffic": ga4, "email_campaigns": email_campaigns, "email_events": email_events,
    "ad_spend": ad_spend,
}
for name, df in outputs.items():
    df.to_csv(OUT / f"{name}.csv", index=False, encoding="utf-8")
    print(f"{name:20s} {len(df):>8,} rows")
print(f"\nDone. Files written to {OUT}")
