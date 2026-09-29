# Instacart Market Basket Analysis

Which products get bought together, which get reordered, and can we predict
the next basket? An end-to-end analytics project on 3M+ grocery orders:
SQL-first analysis in DuckDB, a pandas feature pipeline, a reorder-prediction
model, and a Power BI dashboard.

## Business questions

1. **Basket affinity** — which product pairs are bought together far more
   often than chance? (support / confidence / lift)
2. **Reorder behavior** — which products, aisles, and departments have the
   highest reorder rates, and who are the heavy-reorder customers? (RFM)
3. **When do people shop?** — day-of-week × hour patterns by department.
4. **Can we predict reorders?** — for each product in a user's history,
   will it be in their next order? (binary classification)
5. **Hypothesis test** — do organic products have higher reorder rates than
   conventional equivalents, with a 95% confidence interval on the gap?

## Data

[Instacart Market Basket Analysis](https://www.kaggle.com/c/instacart-market-basket-analysis)
(Kaggle competition, anonymized): ~3.4M orders, 206k users, 49.7k products.

| Table | Rows | Grain |
|---|---|---|
| `aisles` | 134 | one row per aisle |
| `departments` | 21 | one row per department |
| `products` | 49,688 | one row per product |
| `orders` | 3,421,083 | one row per order |
| `order_products__prior` | 32,434,489 | one row per product per prior order |
| `order_products__train` | 1,384,617 | one row per product per train order |

`eval_set` splits orders into `prior` (history), `train` (labeled target),
and `test`. The model trains on prior→train and would score prior+train→test.

Get the data (needs a free Kaggle account + API token):

```bash
python scripts/download_data.py   # -> data/raw/*.csv
```

## Project structure

```
sql/                  SQL-first analysis (runs on DuckDB)
  01_schema.sql         DDL + indexes
  02_basket_affinity.sql  product pairs: support, confidence, lift
  03_reorder_rates.sql    product/department reorder rates (window functions)
  04_user_rfm.sql         recency/frequency/monetary quintiles via NTILE
  05_time_patterns.sql    day-of-week × hour heatmap source
scripts/
  download_data.py      Kaggle download into data/raw/
  build_warehouse.py    CSVs -> data/warehouse.duckdb (typed, indexed)
src/
  features.py           user / product / user×product features (pandas)
  model.py              reorder classifier: logreg baseline -> LightGBM
notebooks/
  01_eda.ipynb          distributions, data-quality checks
  02_reorder_model.ipynb  training, evaluation, error analysis
powerbi/
  README.md             star-schema model, DAX measures, dashboard spec
```

## Reproduce

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scripts/download_data.py
python scripts/build_warehouse.py
# SQL: duckdb data/warehouse.duckdb < sql/02_basket_affinity.sql
python src/model.py
```

## Key techniques

- **SQL** — multi-table joins across a 32M-row fact table, CTEs, window
  functions (`ROW_NUMBER`, `NTILE`, `LAG`, running totals), self-joins for
  pair mining; query plans checked with `EXPLAIN`.
- **Python** — pandas cleaning pipeline (dtypes, nulls, dedupe), feature
  engineering, scikit-learn modeling.
- **Statistics** — two-proportion z-test + CI for the organic-vs-conventional
  question; log-loss/AUC/F1 for the classifier with a train/eval split on
  `eval_set` (no leakage: features use only prior orders).
- **BI** — Power BI star schema + DAX measures (see `powerbi/README.md`).

Educational project — not affiliated with Instacart.
