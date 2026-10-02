# Power BI dashboard — build guide

The `.pbix` itself can't be version-controlled, so this folder holds
everything needed to rebuild it: the star schema as SQL views
(`star_schema.sql`), the DAX measures (`measures.dax`), and the page spec
below. All expected values are from the real 2026-10-02 warehouse run —
use them to sanity-check the build.

## 1. Export the model tables

```bash
duckdb data/warehouse.duckdb < powerbi/star_schema.sql
mkdir -p powerbi/extracts
for v in dim_department dim_aisle dim_product fact_orders fact_lines; do
  duckdb data/warehouse.duckdb \
    "COPY (SELECT * FROM pb_$v) TO 'powerbi/extracts/$v.csv' (HEADER);"
done
```

Import the five CSVs into Power BI Desktop (Import mode). Static SQL
outputs ship as CSVs too — copy from `results/`:

| CSV | Source | Grain |
|---|---|---|
| `basket_affinity.csv` | `sql/02_basket_affinity.sql` | 50 top pairs by lift |
| `user_rfm.csv` | `sql/04_user_rfm.sql` | 5 segments |
| `hypothesis_organic.csv` | `scripts/hypothesis_organic.py` | 20 dept rows + 3 summary rows |

Re-run the `.sql` / `.py` sources and re-import when the warehouse rebuilds.

## 2. Star schema

```
pb_dim_department (1) ──< pb_dim_product >──< pb_fact_lines
pb_dim_aisle      (1) ──< pb_dim_product
                              pb_fact_orders (1) ──< pb_fact_lines_full (DirectQuery only)
```

- Single-direction relationships (dims → facts).
- `pb_fact_lines` grain: product × day-of-week × hour. Additive measures:
  `units`, `reordered_units`. Hide raw columns; expose only measures.
- `pb_dim_product[is_organic]` powers the hypothesis page.
- `order_dow`: 0 = Saturday .. 6 = Friday (there's a `dow_name`/`day_type`).

## 3. DAX measures

Paste `measures.dax` into the model. Every measure carries its expected
value as a comment — if a card disagrees, the import or relationships are
wrong, not the data.

## 4. Dashboard spec (4 pages)

**Page 1 — Executive.** KPI cards: Total Orders (3.42M), Reorder Rate
(~59.0%), Avg Basket Size, Avg Days Between Orders. Bar: reorder rate by
department — dairy eggs 67.0%, beverages 65.4%, produce 65.0% on top;
personal care 32.1% at the bottom. Line: orders by day-of-week (weekend
peak). Slicers: department, aisle, organic.

**Page 2 — Basket affinity.** Table: top-50 pairs by lift (static import).
Expect the top rows to be same-category flavor variants — cottage cheese
flavors at lift ~1696, baby-food pouches, Greek yogurts ("different flavor
of the same staple", tiny support ~500 baskets each). Bar: confidence by
pair. Cross-filter with the department slicer.

**Page 3 — Customer segments.** Donut: RFM segment share — steady 73,731;
champions 45,674 (35.5 orders avg, 5.4d recency); dormant 43,897;
new_promising 23,381; at-risk loyalists 19,526 (~9.5%, 20.2 orders but
26.6d quiet — the win-back target). Matrix: avg orders / units / recency
by segment. Heatmap: orders by dow × hour — peak Sun 10:00 (52,999),
Sat 14:00 (50,484); produce is #1 in all 168 slots.

**Page 4 — Organic hypothesis.** Cards: Organic Reorder Rate (~63.5%),
Conventional (~56.9%), Organic Gap pp (~+6.6). Bar: gap by department —
produce +4.6, bakery +4.3, babies +3.8 vs beverages −3.4, bulk −10.6.
Footnote the honest read: the gap is significant at order-line level
(95% CI [+6.58, +6.65]) and survives department stratification (+4.2pp),
but per-product it's noise (p=0.16) — the effect lives in high-volume
organic staples, not the whole assortment.

## Notes

- Import mode is fine; the aggregated extracts are small. Use DirectQuery
  only via `pb_fact_lines_full` + the DuckDB ODBC connector.
- The `train`/`test` eval sets are excluded from the model — features and
  targets for the reorder model come from `prior`/`train` respectively.
  The trained LightGBM (AUC 0.827) lives in `models/`; its top features
  (recency ≫ habit strength) echo the RFM story on page 3.
