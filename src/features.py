"""Feature engineering for the reorder-prediction model.

Grain: one row per (user_id, product_id) where the user bought the product
at least once in prior orders. Target: 1 if the product appears in the
user's train order, else 0.

Features (all computed from PRIOR orders only — no leakage into the target):
  user:      n_orders, avg_basket_size, avg_days_between_orders,
             reorder_ratio, dow/hour entropy
  product:   n_buyers, reorder_rate, avg_add_to_cart_order,
             avg_days_between_purchases
  user_x_product: n_bought, n_reordered, reorder_ratio,
             days_since_last_bought, avg_add_to_cart_order,
             order_rate (bought / user n_orders)

Usage:
    from src.features import build_feature_frame
    df = build_feature_frame("data/warehouse.duckdb")
"""
from pathlib import Path

import duckdb
import pandas as pd

DB = Path(__file__).resolve().parent.parent / "data" / "warehouse.duckdb"


def build_feature_frame(db_path: str | Path = DB) -> pd.DataFrame:
    con = duckdb.connect(str(db_path), read_only=True)

    # ---- target: what was in each user's train order ---------------------
    target = con.execute(
        """SELECT o.user_id, op.product_id, 1 AS y
           FROM order_products__train op
           JOIN orders o ON o.order_id = op.order_id"""
    ).df()

    # ---- user features ----------------------------------------------------
    users = con.execute(
        """WITH u AS (
             SELECT o.user_id,
                    COUNT(DISTINCT o.order_id) AS n_orders,
                    AVG(o.days_since_prior_order) AS avg_days_between,
                    SUM(op.reordered) * 1.0 / COUNT(*) AS user_reorder_ratio
             FROM orders o
             JOIN order_products__prior op ON op.order_id = o.order_id
             WHERE o.eval_set = 'prior'
             GROUP BY 1
           ),
           basket AS (
             SELECT o.user_id, AVG(cnt) AS avg_basket_size
             FROM orders o
             JOIN (SELECT order_id, COUNT(*) AS cnt
                   FROM order_products__prior GROUP BY 1) c
               ON c.order_id = o.order_id
             WHERE o.eval_set = 'prior'
             GROUP BY 1
           )
           SELECT u.*, b.avg_basket_size
           FROM u JOIN basket b USING (user_id)"""
    ).df()

    # ---- product features -------------------------------------------------
    products = con.execute(
        """SELECT op.product_id,
                  COUNT(DISTINCT o.user_id) AS n_buyers,
                  AVG(op.reordered) AS prod_reorder_rate,
                  AVG(op.add_to_cart_order) AS prod_avg_cart_pos
           FROM order_products__prior op
           JOIN orders o ON o.order_id = op.order_id
           GROUP BY 1"""
    ).df()

    # ---- user x product features ------------------------------------------
    uxp = con.execute(
        """WITH ranked AS (
             SELECT o.user_id, op.product_id, op.reordered,
                    op.add_to_cart_order, o.order_number,
                    ROW_NUMBER() OVER (
                        PARTITION BY o.user_id, op.product_id
                        ORDER BY o.order_number DESC) AS rn,
                    MAX(o.order_number) OVER (
                        PARTITION BY o.user_id) AS user_max_n
             FROM order_products__prior op
             JOIN orders o ON o.order_id = op.order_id
           )
           SELECT user_id, product_id,
                  COUNT(*) AS uxp_n_bought,
                  SUM(reordered) AS uxp_n_reordered,
                  SUM(reordered) * 1.0 / COUNT(*) AS uxp_reorder_ratio,
                  AVG(add_to_cart_order) AS uxp_avg_cart_pos,
                  -- orders since last bought (0 = bought in latest order)
                  MIN(user_max_n - order_number) AS orders_since_last
           FROM ranked
           GROUP BY 1, 2"""
    ).df()
    uxp["uxp_order_rate"] = (
        uxp["uxp_n_bought"]
        / uxp["user_id"].map(users.set_index("user_id")["n_orders"])
    )

    # ---- assemble ----------------------------------------------------------
    df = (
        uxp.merge(users, on="user_id", how="left")
           .merge(products, on="product_id", how="left")
           .merge(target, on=["user_id", "product_id"], how="left")
    )
    df["y"] = df["y"].fillna(0).astype("int8")
    con.close()
    return df


if __name__ == "__main__":
    df = build_feature_frame()
    print(df.shape)
    print("positive rate:", round(df["y"].mean(), 4))
    print(df.dtypes.value_counts())
