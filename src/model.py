"""Reorder classifier: will this (user, product) pair appear in the
user's next (train) order?

Pipeline: build features (prior orders only) -> train/validation split by
user_id -> logistic-regression baseline -> LightGBM -> report log-loss,
AUC, F1 and the top features.

    python src/model.py

No leakage by construction: every feature is computed from eval_set='prior'
orders; the target comes from eval_set='train' orders.
"""
from pathlib import Path

import lightgbm as lgb
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import f1_score, log_loss, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

from features import build_feature_frame

BASE = Path(__file__).resolve().parent.parent
FEATURES = [
    "n_orders", "avg_days_between", "user_reorder_ratio", "avg_basket_size",
    "n_buyers", "prod_reorder_rate", "prod_avg_cart_pos",
    "uxp_n_bought", "uxp_n_reordered", "uxp_reorder_ratio",
    "uxp_avg_cart_pos", "orders_since_last", "uxp_order_rate",
]


def evaluate(name: str, y_true: pd.Series, proba) -> None:
    pred = (proba >= 0.5).astype(int)
    print(f"{name:12s} logloss={log_loss(y_true, proba):.4f} "
          f"AUC={roc_auc_score(y_true, proba):.4f} "
          f"F1={f1_score(y_true, pred):.4f}")


def main() -> None:
    print("building features ...")
    df = build_feature_frame(BASE / "data" / "warehouse.duckdb")
    df = df.dropna(subset=FEATURES)
    X, y = df[FEATURES], df["y"]
    print(f"rows={len(df):,}  positive rate={y.mean():.4f}")

    # Split by user so no user appears on both sides.
    users = df["user_id"].unique()
    tr_u, va_u = train_test_split(users, test_size=0.2, random_state=42)
    tr = df["user_id"].isin(tr_u)
    X_tr, y_tr, X_va, y_va = X[tr], y[tr], X[~tr], y[~tr]

    # Baseline: logistic regression on standardized features.
    scaler = StandardScaler().fit(X_tr)
    logreg = LogisticRegression(max_iter=500, C=1.0).fit(scaler.transform(X_tr), y_tr)
    evaluate("logreg", y_va, logreg.predict_proba(scaler.transform(X_va))[:, 1])

    # Gradient boosting.
    dtrain = lgb.Dataset(X_tr, label=y_tr)
    dvalid = lgb.Dataset(X_va, label=y_va, reference=dtrain)
    params = {"objective": "binary", "metric": "binary_logloss",
              "learning_rate": 0.05, "num_leaves": 64,
              "feature_fraction": 0.8, "bagging_fraction": 0.8,
              "bagging_freq": 1, "verbosity": -1, "seed": 42}
    gbm = lgb.train(params, dtrain, num_boost_round=400,
                    valid_sets=[dvalid],
                    callbacks=[lgb.early_stopping(30, verbose=False)])
    proba = gbm.predict(X_va, num_iteration=gbm.best_iteration)
    evaluate("lightgbm", y_va, proba)

    print("\ntop features (gain):")
    imp = pd.Series(gbm.feature_importance(importance_type="gain"),
                    index=FEATURES).sort_values(ascending=False)
    print(imp.head(10).round(0).astype(int).to_string())


if __name__ == "__main__":
    main()
