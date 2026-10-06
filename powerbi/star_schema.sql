-- Star-schema views for the Power BI model (Instacart basket analysis).
--
-- Run:  duckdb data/warehouse.duckdb < powerbi/star_schema.sql
-- then COPY each pb_* view to CSV for Power BI Desktop import, e.g.
--   COPY (SELECT * FROM pb_dim_product) TO 'powerbi/extracts/dim_product.csv' (HEADER);
--
-- order_dow convention: 0 = Saturday .. 6 = Friday.

CREATE OR REPLACE VIEW pb_dim_department AS
SELECT department_id, department
FROM departments;

CREATE OR REPLACE VIEW pb_dim_aisle AS
SELECT aisle_id, aisle
FROM aisles;

CREATE OR REPLACE VIEW pb_dim_product AS
SELECT p.product_id,
       p.product_name,
       p.aisle_id,
       p.department_id,
       a.aisle,
       d.department,
       (p.product_name ILIKE '%organic%') AS is_organic
FROM products p
JOIN aisles a USING (aisle_id)
JOIN departments d USING (department_id);

-- One row per prior order (3,421,083 rows).
CREATE OR REPLACE VIEW pb_fact_orders AS
SELECT order_id,
       user_id,
       order_number,
       order_dow,
       order_hour_of_day,
       days_since_prior_order,
       CASE order_dow
           WHEN 0 THEN 'Sat' WHEN 1 THEN 'Sun' WHEN 2 THEN 'Mon'
           WHEN 3 THEN 'Tue' WHEN 4 THEN 'Wed' WHEN 5 THEN 'Thu'
           ELSE 'Fri'
       END AS dow_name,
       CASE WHEN order_dow IN (0, 1) THEN 'Weekend' ELSE 'Weekday' END AS day_type
FROM orders
WHERE eval_set = 'prior';

-- Aggregated fact at product x day-of-week x hour grain.
-- Keeps the CSV extract small (~2.4M rows worst case); the full 32M-row
-- grain is pb_fact_lines_full below, for DirectQuery via ODBC if needed.
CREATE OR REPLACE VIEW pb_fact_lines AS
SELECT op.product_id,
       o.order_dow,
       o.order_hour_of_day,
       CASE o.order_dow
           WHEN 0 THEN 'Sat' WHEN 1 THEN 'Sun' WHEN 2 THEN 'Mon'
           WHEN 3 THEN 'Tue' WHEN 4 THEN 'Wed' WHEN 5 THEN 'Thu'
           ELSE 'Fri'
       END AS dow_name,
       COUNT(*) AS units,
       SUM(op.reordered) AS reordered_units
FROM order_products__prior op
JOIN orders o USING (order_id)
WHERE o.eval_set = 'prior'
GROUP BY 1, 2, 3, 4;

-- Full-grain fact (32,434,489 rows). Only for DirectQuery; do NOT export to CSV.
CREATE OR REPLACE VIEW pb_fact_lines_full AS
SELECT op.order_id, op.product_id, op.add_to_cart_order, op.reordered,
       o.user_id, o.order_dow, o.order_hour_of_day
FROM order_products__prior op
JOIN orders o USING (order_id)
WHERE o.eval_set = 'prior';
