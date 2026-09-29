-- 01_schema.sql — DDL for the Instacart warehouse (DuckDB).
-- Load order: dimensions first, then orders, then the two fact tables.
-- Run: duckdb data/warehouse.duckdb < sql/01_schema.sql

CREATE TABLE IF NOT EXISTS aisles (
    aisle_id   INTEGER PRIMARY KEY,
    aisle      VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS departments (
    department_id INTEGER PRIMARY KEY,
    department    VARCHAR NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
    product_id    INTEGER PRIMARY KEY,
    product_name  VARCHAR NOT NULL,
    aisle_id      INTEGER NOT NULL REFERENCES aisles (aisle_id),
    department_id INTEGER NOT NULL REFERENCES departments (department_id)
);

CREATE TABLE IF NOT EXISTS orders (
    order_id               INTEGER PRIMARY KEY,
    user_id                INTEGER NOT NULL,
    eval_set               VARCHAR NOT NULL,   -- prior | train | test
    order_number           INTEGER NOT NULL,   -- nth order for this user
    order_dow              INTEGER NOT NULL,   -- 0 = Saturday .. 6 = Friday
    order_hour_of_day      INTEGER NOT NULL,
    days_since_prior_order DOUBLE              -- NULL on first order
);

CREATE TABLE IF NOT EXISTS order_products__prior (
    order_id         INTEGER NOT NULL REFERENCES orders (order_id),
    product_id       INTEGER NOT NULL REFERENCES products (product_id),
    add_to_cart_order INTEGER NOT NULL,
    reordered        INTEGER NOT NULL          -- 1 if user bought it before
);

CREATE TABLE IF NOT EXISTS order_products__train (
    order_id         INTEGER NOT NULL REFERENCES orders (order_id),
    product_id       INTEGER NOT NULL REFERENCES products (product_id),
    add_to_cart_order INTEGER NOT NULL,
    reordered        INTEGER NOT NULL
);

-- Indexes for the heavy joins (fact -> dims, orders -> users).
-- The 32M-row prior table is the one that makes these pay off;
-- check with EXPLAIN before/after on sql/02_basket_affinity.sql.
CREATE INDEX IF NOT EXISTS idx_prior_order   ON order_products__prior (order_id);
CREATE INDEX IF NOT EXISTS idx_prior_product ON order_products__prior (product_id);
CREATE INDEX IF NOT EXISTS idx_train_order   ON order_products__train (order_id);
CREATE INDEX IF NOT EXISTS idx_train_product ON order_products__train (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_user   ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_eval   ON orders (eval_set);
CREATE INDEX IF NOT EXISTS idx_products_dept ON products (department_id);
