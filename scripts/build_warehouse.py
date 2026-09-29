"""Build the DuckDB warehouse from the raw Kaggle CSVs.

    python scripts/build_warehouse.py

Reads data/raw/*.csv, applies dtypes, and writes data/warehouse.duckdb
using the DDL in sql/01_schema.sql. Validates row counts + FK coverage
after load and prints a short report.
"""
from pathlib import Path

import duckdb

BASE = Path(__file__).resolve().parent.parent
RAW = BASE / "data" / "raw"
DB = BASE / "data" / "warehouse.duckdb"
SCHEMA_SQL = BASE / "sql" / "01_schema.sql"

EXPECTED = {
    "aisles": 134,
    "departments": 21,
    "products": 49688,
    "orders": 3421083,
}


def main() -> None:
    missing = [f"{t}.csv" for t in EXPECTED if not (RAW / f"{t}.csv").exists()]
    if missing:
        raise SystemExit(
            f"missing raw files: {missing}\nrun: python scripts/download_data.py")

    if DB.exists():
        DB.unlink()
    con = duckdb.connect(str(DB))
    con.execute(SCHEMA_SQL.read_text())

    # Dimensions: small, direct insert.
    for table in ("aisles", "departments", "products"):
        con.execute(
            f"INSERT INTO {table} SELECT * FROM read_csv('{RAW}/{table}.csv', header=true)")
        n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        exp = EXPECTED[table]
        print(f"{table:12s} {n:>10,} rows", "OK" if n == exp else f"MISMATCH (expected {exp:,})")

    # Orders: days_since_prior_order is empty on first orders -> DOUBLE NULL.
    con.execute(
        f"""INSERT INTO orders
            SELECT * FROM read_csv('{RAW}/orders.csv', header=true,
                columns={{'order_id':'INTEGER','user_id':'INTEGER',
                          'eval_set':'VARCHAR','order_number':'INTEGER',
                          'order_dow':'INTEGER','order_hour_of_day':'INTEGER',
                          'days_since_prior_order':'DOUBLE'}})""")
    n = con.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    print(f"{'orders':12s} {n:>10,} rows",
          "OK" if n == EXPECTED["orders"] else "MISMATCH")

    # Facts: the big ones. ~32M rows for prior — takes a few minutes.
    for table in ("order_products__prior", "order_products__train"):
        con.execute(
            f"INSERT INTO {table} SELECT * FROM read_csv('{RAW}/{table}.csv', header=true)")
        n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"{table:12s} {n:>10,} rows")

    # FK coverage: every fact row must resolve to a real product/order.
    orphans = con.execute(
        """SELECT COUNT(*) FROM order_products__prior op
           LEFT JOIN products p ON p.product_id = op.product_id
           WHERE p.product_id IS NULL""").fetchone()[0]
    print("orphan prior rows:", orphans, "(must be 0)")
    assert orphans == 0

    con.execute("CHECKPOINT")
    con.close()
    print("warehouse ready:", DB)


if __name__ == "__main__":
    main()
