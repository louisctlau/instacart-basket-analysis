-- 03_reorder_rates.sql — reorder rates by product and department,
-- with window functions for ranking and share.
--
-- reorder = 1 when the user had bought the product in an earlier order.
-- Run: duckdb data/warehouse.duckdb < sql/03_reorder_rates.sql

-- Per-product reorder rate, ranked within department
WITH product_stats AS (
    SELECT
        p.product_id,
        p.product_name,
        d.department,
        COUNT(*)              AS times_ordered,
        AVG(op.reordered)     AS reorder_rate
    FROM order_products__prior op
    JOIN products p      ON p.product_id = op.product_id
    JOIN departments d   ON d.department_id = p.department_id
    GROUP BY 1, 2, 3
    HAVING COUNT(*) >= 1000          -- stable estimates only
)
SELECT
    department,
    product_name,
    times_ordered,
    ROUND(reorder_rate, 4) AS reorder_rate,
    RANK() OVER (
        PARTITION BY department ORDER BY reorder_rate DESC
    ) AS dept_rank
FROM product_stats
QUALIFY dept_rank <= 5               -- top-5 most reordered per department
ORDER BY department, dept_rank;

-- Department-level reorder rate + share of all reordered units
WITH dept_stats AS (
    SELECT
        d.department,
        COUNT(*)          AS units,
        AVG(op.reordered) AS reorder_rate
    FROM order_products__prior op
    JOIN products p    ON p.product_id = op.product_id
    JOIN departments d ON d.department_id = p.department_id
    GROUP BY 1
)
SELECT
    department,
    units,
    ROUND(reorder_rate, 4) AS reorder_rate,
    ROUND(
        SUM(units * reorder_rate) OVER ()
        / SUM(units) OVER (), 4
    ) AS overall_reorder_rate,
    ROUND(
        100.0 * units * reorder_rate
        / SUM(units * reorder_rate) OVER (), 2
    ) AS pct_of_all_reorders
FROM dept_stats
ORDER BY reorder_rate DESC;
