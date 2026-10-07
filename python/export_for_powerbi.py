"""
Exports the reporting layer (dim_ / fct_ tables and any vw_ views) to CSV so
Power BI Desktop can load them with Get Data > Text/CSV (or Folder).

  python python/export_for_powerbi.py
Output: exports/*.csv
"""
import sqlite3
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
con = sqlite3.connect(ROOT / "data" / "retail.db")
out = ROOT / "exports"; out.mkdir(exist_ok=True)
objs = pd.read_sql("""SELECT name FROM sqlite_master
                      WHERE type IN ('table','view')
                        AND (name LIKE 'dim\\_%' ESCAPE '\\' OR name LIKE 'fct\\_%' ESCAPE '\\'
                             OR name LIKE 'vw\\_%' ESCAPE '\\')""", con).name
for n in objs:
    df = pd.read_sql(f"SELECT * FROM {n}", con)
    df.to_csv(out / f"{n}.csv", index=False, encoding="utf-8")
    print(f"  {n:28s} {len(df):>8,} rows")
print(f"\nExported {len(objs)} objects to {out}")
