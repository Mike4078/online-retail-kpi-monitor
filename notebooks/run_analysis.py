"""
Fallback for notebooks/01_exploration.ipynb - same analysis, no Jupyter needed.
Run from the project folder:   python notebooks/run_analysis.py
"""
import sqlite3
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "retail.db"
if not DB.exists():
    raise SystemExit(f"Database not found at {DB}. Run python/build_database.py first.")
con = sqlite3.connect(DB)
tables = set(pd.read_sql("SELECT name FROM sqlite_master WHERE type='table'", con).name)
if "fct_order_items" not in tables:
    raise SystemExit("fct_order_items is missing. Run sql/03 and sql/04 in DBeaver first (Part A).")

# 1. First look at the raw orders
orders = pd.read_sql("SELECT * FROM raw_orders", con)
print("raw_orders shape:", orders.shape)
print(orders["status"].value_counts(), "\n")
print(orders["platform"].value_counts(normalize=True).round(3), "\n")

# 2. Daily orders by platform
daily = pd.read_sql("""
    SELECT d.date, p.platform,
           COUNT(DISTINCT f.order_id) AS orders
    FROM dim_date d
    CROSS JOIN (SELECT 'web' AS platform UNION ALL SELECT 'app') p
    LEFT JOIN fct_order_items f
           ON f.order_date = d.date AND f.platform = p.platform AND f.status <> 'cancelled'
    GROUP BY d.date, p.platform
""", con, parse_dates=["date"])
wide = daily.pivot(index="date", columns="platform", values="orders")

ax = wide.plot(figsize=(14, 4), title="Daily orders by platform")
ax.axvspan(pd.Timestamp("2026-03-09"), pd.Timestamp("2026-03-15"), color="red", alpha=0.15, label="App data missing")
ax.legend()
plt.tight_layout()
out = ROOT / "powerbi" / "screenshots" / "daily_orders_by_platform.png"
out.parent.mkdir(parents=True, exist_ok=True)
plt.savefig(out, dpi=120)
print("Chart saved to", out, "\n")

# 3. Rolling z-score (A-04): distance from the previous 28 days, in standard deviations
roll_mean = wide.rolling(28, min_periods=14).mean().shift(1)   # shift(1): today not in its own baseline
roll_std = wide.rolling(28, min_periods=14).std().shift(1)
z = (wide - roll_mean) / roll_std
flags = z[(z.abs() > 3).any(axis=1)].round(1)
print("Days with |z| > 3:")
print(flags)
