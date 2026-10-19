# Reorder model training

Re-trained 2026-10-07 on the full frame from the real warehouse
(`data/warehouse.duckdb`) — no synthetic data. This supersedes the
2026-10-02 run, which used a deterministic 15% user sample (validation
AUC 0.8272 on that sample); the full-frame scores below are the numbers
quoted in the README, notebooks, and resume (LightGBM validation AUC
0.817).

## Setup
- Grain: one row per (user_id, product_id) bought at least once in prior
  orders; target = 1 if the product is in the user's train order.
- Sample: none — full frame: 13,307,953 rows, positive rate 0.0623.
- Split: 80/20 by user_id (no user on both sides), seed 42 →
  train 10,643,731 rows, valid 2,664,222 rows.
- Missing values: none in the built frame (all features complete from
  prior-order histories).
- Models: logistic-regression baseline (standardized, C=1.0) → LightGBM
  binary, lr=0.05, 64 leaves, up to 400 rounds, early stopping (30).
  See `src/model.py`; the notebook re-runs the same pipeline.

## Scores (validation)

| model | logloss | AUC | F1@0.5 |
|---|---|---|---|
| logreg | 0.1923 | 0.8107 | 0.0469 |
| lightgbm | 0.1893 | 0.8170 | 0.0302 |

Positive rate (full frame): 0.0623.

## Top features (gain)

| # | feature | gain |
|---|---|---|
| 1 | orders_since_last | 3,222,616 |
| 2 | uxp_order_rate | 2,693,579 |
| 3 | uxp_n_bought | 624,787 |
| 4 | prod_reorder_rate | 383,101 |
| 5 | uxp_n_reordered | 262,177 |
| 6 | user_reorder_ratio | 203,669 |
| 7 | n_buyers | 94,668 |
| 8 | avg_days_between | 81,610 |
| 9 | avg_basket_size | 62,989 |
| 10 | n_orders | 58,129 |

## Artifacts
- `models/reorder_lgbm.txt` — trained booster (saved from the earlier
  2026-10-02 15%-sample run; not re-saved for the full-frame run)
- `models/metrics.json` — metrics, importances, impute medians, params
  (likewise from the 2026-10-02 sample run)
