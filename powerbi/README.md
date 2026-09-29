# Power BI dashboard — build guide

The `.pbix` itself can't be version-controlled, so this folder documents
everything needed to rebuild it: the star schema, the DAX measures, and
the page spec. Export the model tables from DuckDB first:

```sql
COPY (SELECT * FROM orders WHERE eval_set = 'prior') TO 'powerbi/fact_orders.csv' (HEADER);
COPY (SELECT * FROM order_products__prior)           TO 'powerbi/fact_lines.csv'  (HEADER);
COPY (SELECT * FROM products)                       TO 'powerbi/dim_product.csv'   (HEADER);
COPY (SELECT * FROM aisles)                         TO 'powerbi/dim_aisle.csv'     (HEADER);
COPY (SELECT * FROM departments)                    TO 'powerbi/dim_department.csv'(HEADER);
```

(The 32M-row fact_lines is ~1 GB as CSV — aggregate to product/day grain
first if Power BI Desktop struggles: group by product_id, order_dow,
order_hour_of_day with SUM(reordered) / COUNT(*).)

## Star schema

```
dim_department (1) ──< dim_product >──< fact_lines
dim_aisle      (1) ──< dim_product        fact_orders (1) ──< fact_lines
```

- Relationships are single-direction (dims → facts).
- `fact_lines` grain: one row per product per order. Additive measures:
  `Units = COUNTROWS`, `ReorderedUnits = SUM(reordered)`.
- Hide the raw `reordered` column; expose only measures.

## DAX measures

```dax
Total Orders =
DISTINCTCOUNT ( fact_orders[order_id] )

Total Units =
COUNTROWS ( fact_lines )

Reorder Rate =
DIVIDE ( SUM ( fact_lines[reordered] ), [Total Units] )

Avg Basket Size =
DIVIDE ( [Total Units], [Total Orders] )

Avg Days Between Orders =
AVERAGE ( fact_orders[days_since_prior_order] )

Top Product Reorder Rate =
-- reorder rate of the best product in the current filter context
MAXX (
    VALUES ( dim_product[product_name] ),
    CALCULATE ( [Reorder Rate] )
)

Orders WoW % =
-- needs a proper date table; order_dow alone can't do WoW.
-- Build dim_date from order_number sequences per user instead,
-- or accept the dow/hour heatmap as the time view.
VAR CurrDow = SELECTEDVALUE ( fact_orders[order_dow] )
RETURN
    DIVIDE (
        [Total Orders]
            - CALCULATE ( [Total Orders], fact_orders[order_dow] = CurrDow - 1 ),
        CALCULATE ( [Total Orders], fact_orders[order_dow] = CurrDow - 1 )
    )
```

## Dashboard spec (3 pages)

**Page 1 — Executive.** KPI cards: Total Orders, Reorder Rate, Avg Basket
Size, Avg Days Between Orders. Bar: reorder rate by department. Line:
orders by day-of-week. Slicers: department, aisle.

**Page 2 — Basket affinity.** Table: top-50 product pairs by lift (from
`sql/02_basket_affinity.sql`, imported as a static table). Bar: confidence
by pair. Cross-filter with the department slicer.

**Page 3 — Customer segments.** Donut: RFM segment share (from
`sql/04_user_rfm.sql`, static import). Matrix: avg orders / units /
recency by segment. Heatmap: orders by dow × hour (from
`sql/05_time_patterns.sql`).

## Notes

- Import mode is fine; the aggregated extracts are small. Use DirectQuery
  only if you keep the full 32M-row fact in DuckDB via the ODBC connector.
- The pair/segment tables are SQL outputs imported statically — re-run the
  `.sql` files and refresh when the warehouse rebuilds.
