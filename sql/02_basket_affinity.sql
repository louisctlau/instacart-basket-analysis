-- 02_basket_affinity.sql — which product pairs are bought together
-- far more often than chance? (support / confidence / lift)
--
-- Technique: self-join the 32M-row prior fact on order_id, then aggregate.
-- Run: duckdb data/warehouse.duckdb < sql/02_basket_affinity.sql

WITH pair_counts AS (
    -- unordered product pairs per basket (a < b avoids double counting)
    SELECT
        a.product_id AS product_a,
        b.product_id AS product_b,
        COUNT(*)     AS pair_orders
    FROM order_products__prior a
    JOIN order_products__prior b
      ON a.order_id = b.order_id
     AND a.product_id < b.product_id
    GROUP BY 1, 2
),
product_orders AS (
    -- how many baskets contain each product (for the lift denominator)
    SELECT product_id, COUNT(DISTINCT order_id) AS orders_with_product
    FROM order_products__prior
    GROUP BY 1
),
total AS (
    SELECT COUNT(DISTINCT order_id) AS n_orders
    FROM order_products__prior
)
SELECT
    pa.product_name                        AS product_a,
    pb.product_name                        AS product_b,
    pc.pair_orders,
    ROUND(pc.pair_orders * 1.0 / t.n_orders, 5)                       AS support,
    ROUND(pc.pair_orders * 1.0 / po_a.orders_with_product, 4)         AS confidence_a_given_b,
    ROUND(
        (pc.pair_orders * 1.0 / t.n_orders)
        / ((po_a.orders_with_product * 1.0 / t.n_orders)
         * (po_b.orders_with_product * 1.0 / t.n_orders)),
        2
    ) AS lift
FROM pair_counts pc
JOIN product_orders po_a ON po_a.product_id = pc.product_a
JOIN product_orders po_b ON po_b.product_id = pc.product_b
JOIN products pa ON pa.product_id = pc.product_a
JOIN products pb ON pb.product_id = pc.product_b
CROSS JOIN total t
WHERE pc.pair_orders >= 500          -- minimum support: noise filter
ORDER BY lift DESC
LIMIT 50;
