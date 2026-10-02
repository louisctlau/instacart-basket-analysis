-- 04_user_rfm.sql — customer segmentation, RFM style.
--
-- Recency  = days since the user's last order
-- Frequency = total orders placed
-- Monetary  = proxied by total units bought (no prices in this dataset)
-- Quintiles via NTILE, then a segment label from the R/F/M scores.
-- Run: duckdb data/warehouse.duckdb < sql/04_user_rfm.sql

WITH user_stats AS (
    SELECT
        o.user_id,
        COUNT(DISTINCT o.order_id)        AS n_orders,
        SUM(op.units)                     AS total_units,
        -- recency: days since prior order on the user's latest order;
        -- single-order users get a large value (least recent)
        COALESCE(
            MAX(CASE WHEN o.order_number = mu.max_n
                     THEN o.days_since_prior_order END),
            9999
        ) AS recency_days
    FROM orders o
    JOIN (
        SELECT order_id, COUNT(*) AS units
        FROM order_products__prior
        GROUP BY 1
    ) op ON op.order_id = o.order_id
    JOIN (
        -- max_n over PRIOR orders only: the outer query filters to
        -- eval_set='prior', and every user's overall max order_number sits
        -- in train/test, so an unfiltered MAX() never matches and every
        -- user got recency 9999 on the real data.
        SELECT user_id, MAX(order_number) AS max_n
        FROM orders
        WHERE eval_set = 'prior'
        GROUP BY 1
    ) mu ON mu.user_id = o.user_id
    WHERE o.eval_set = 'prior'
    GROUP BY 1
),
scored AS (
    SELECT
        user_id,
        n_orders,
        total_units,
        recency_days,
        -- NTILE bucket 1 holds the "best" rows by the sort key, so invert:
        -- the segment CASE below expects high score = recent/frequent/big.
        6 - NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,  -- low days = high score
        6 - NTILE(5) OVER (ORDER BY n_orders DESC)     AS f_score,
        6 - NTILE(5) OVER (ORDER BY total_units DESC)  AS m_score
    FROM user_stats
)
SELECT
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN 'champions'
        WHEN f_score >= 4 AND r_score <= 2 THEN 'at_risk_loyalists'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'new_promising'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'dormant'
        ELSE 'steady'
    END AS segment,
    COUNT(*)                          AS users,
    ROUND(AVG(n_orders), 1)            AS avg_orders,
    ROUND(AVG(total_units), 1)         AS avg_units,
    ROUND(AVG(recency_days), 1)       AS avg_recency_days
FROM scored
GROUP BY 1
ORDER BY users DESC;
