-- 05_time_patterns.sql — when do people shop?
-- Day-of-week x hour order counts, plus the top department per time slot.
-- (Feeds the Power BI heatmap.) Run:
--   duckdb data/warehouse.duckdb < sql/05_time_patterns.sql

-- Overall traffic grid
SELECT
    order_dow,
    order_hour_of_day AS hr,
    COUNT(*) AS n_orders,
    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (PARTITION BY order_dow), 1
    ) AS pct_of_day
FROM orders
WHERE eval_set = 'prior'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Top department in each day/hour slot (window function pick)
WITH slot_dept AS (
    SELECT
        o.order_dow,
        o.order_hour_of_day AS hr,
        d.department,
        COUNT(*) AS units
    FROM orders o
    JOIN order_products__prior op ON op.order_id = o.order_id
    JOIN products p  ON p.product_id = op.product_id
    JOIN departments d ON d.department_id = p.department_id
    WHERE o.eval_set = 'prior'
    GROUP BY 1, 2, 3
)
SELECT order_dow, hr, department, units
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY order_dow, hr ORDER BY units DESC
        ) AS rn
    FROM slot_dept
)
WHERE rn = 1
ORDER BY order_dow, hr;
