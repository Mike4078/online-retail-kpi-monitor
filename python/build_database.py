"""
Builds the SQLite database from the raw CSV exports.

  python python/build_database.py            -> creates raw_ tables + loads CSVs
  python python/build_database.py --all      -> also runs sql/03 and sql/04
                                                 (once you have written them)

Database file: data/retail.db  (open it in DBeaver or DB Browser for SQLite)
"""
import sqlite3, sys
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "retail.db"
RAW = ROOT / "data" / "raw"
SQL = ROOT / "sql"

def run_sql_file(con, name):
    print(f"  running {name}")
    con.executescript((SQL / name).read_text(encoding="utf-8"))

def main():
    if not (RAW / "orders.csv").exists():
        sys.exit("Raw CSVs not found. Run: python python/generate_data.py")
    con = sqlite3.connect(DB)
    run_sql_file(con, "01_raw_schema.sql")
    for csv in sorted(RAW.glob("*.csv")):
        df = pd.read_csv(csv, dtype=str, keep_default_na=False, na_values=[""])  # keep raw values as-is
        df.to_sql(f"raw_{csv.stem}", con, if_exists="append", index=False)
        print(f"  loaded raw_{csv.stem:22s} {len(df):>8,} rows")
    if "--all" in sys.argv:
        for f in ["02_data_quality_checks.sql", "03_clean_layer.sql", "04_star_schema.sql", "05_kpi_analysis.sql", "06_anomaly_detection.sql"]:
            run_sql_file(con, f)
    con.commit(); con.close()
    print(f"\nDatabase ready: {DB}")

if __name__ == "__main__":
    main()
