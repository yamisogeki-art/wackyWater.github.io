"""
Trains both LightGBM and XGBoost on the feature set using a
chronological (not random) train/val split -- since this is a time
series, shuffling would leak future information into training.

Split: last 30 days = validation set (mirrors a realistic "predict the
next month" evaluation), everything before = training set.

Evaluates MAE, RMSE, MAPE on the validation set for both models,
saves the trained models, and picks the better one as the thesis's
production model.
"""

import numpy as np
import pandas as pd
import lightgbm as lgb
import xgboost as xgb
from sklearn.metrics import mean_absolute_error, mean_squared_error
import joblib
import json

df = pd.read_csv("data/features.csv",
                  parse_dates=["transaction_date"])

FEATURE_COLS = [
    "lag_1", "lag_7", "lag_14",
    "rolling_mean_7", "rolling_std_7", "rolling_mean_14",
    "day_of_week", "month", "day",
    "is_weekend", "is_payday_window", "is_dry_season",
]
TARGET_COL = "gallons_dispensed"

VAL_DAYS = 30
train_df = df.iloc[:-VAL_DAYS].reset_index(drop=True)
val_df = df.iloc[-VAL_DAYS:].reset_index(drop=True)

X_train, y_train = train_df[FEATURE_COLS], train_df[TARGET_COL]
X_val, y_val = val_df[FEATURE_COLS], val_df[TARGET_COL]

print(f"Train: {len(X_train)} rows ({train_df.transaction_date.min().date()} to {train_df.transaction_date.max().date()})")
print(f"Val:   {len(X_val)} rows ({val_df.transaction_date.min().date()} to {val_df.transaction_date.max().date()})")


def evaluate(y_true, y_pred, name):
    mae = mean_absolute_error(y_true, y_pred)
    rmse = np.sqrt(mean_squared_error(y_true, y_pred))
    mape = np.mean(np.abs((y_true - y_pred) / y_true)) * 100
    print(f"\n{name}")
    print(f"  MAE:  {mae:.2f} gallons")
    print(f"  RMSE: {rmse:.2f} gallons")
    print(f"  MAPE: {mape:.2f}%")
    return {"mae": round(mae, 3), "rmse": round(rmse, 3), "mape": round(mape, 3)}


# --- LightGBM ---
lgb_train = lgb.Dataset(X_train, label=y_train)
lgb_val = lgb.Dataset(X_val, label=y_val, reference=lgb_train)

lgb_params = {
    "objective": "regression",
    "metric": "mae",
    "num_leaves": 15,
    "learning_rate": 0.05,
    "min_data_in_leaf": 5,
    "verbosity": -1,
}

lgb_model = lgb.train(
    lgb_params,
    lgb_train,
    num_boost_round=500,
    valid_sets=[lgb_val],
    callbacks=[lgb.early_stopping(30, verbose=False)],
)

lgb_pred = lgb_model.predict(X_val)
lgb_metrics = evaluate(y_val.values, lgb_pred, "LightGBM")

# --- XGBoost ---
xgb_model = xgb.XGBRegressor(
    n_estimators=500,
    learning_rate=0.05,
    max_depth=4,
    min_child_weight=3,
    objective="reg:squarederror",
    early_stopping_rounds=30,
)
xgb_model.fit(
    X_train, y_train,
    eval_set=[(X_val, y_val)],
    verbose=False,
)

xgb_pred = xgb_model.predict(X_val)
xgb_metrics = evaluate(y_val.values, xgb_pred, "XGBoost")

# --- Pick winner on MAPE (most interpretable for a defense) ---
winner = "lightgbm" if lgb_metrics["mape"] <= xgb_metrics["mape"] else "xgboost"
print(f"\n{'='*40}")
print(f"Winner: {winner.upper()} (lower MAPE)")
print(f"{'='*40}")

# Save both models
joblib.dump(lgb_model, "models/lightgbm_model.pkl")
xgb_model.save_model("models/xgboost_model.json")

# Save comparison metrics + feature list for the manuscript / API
results = {
    "lightgbm": lgb_metrics,
    "xgboost": xgb_metrics,
    "winner": winner,
    "feature_columns": FEATURE_COLS,
    "val_days": VAL_DAYS,
}
with open("outputs/model_comparison.json", "w") as f:
    json.dump(results, f, indent=2)

# Save predictions for a comparison chart
val_out = val_df[["transaction_date", "gallons_dispensed"]].copy()
val_out["lightgbm_pred"] = lgb_pred
val_out["xgboost_pred"] = xgb_pred
val_out.to_csv("outputs/val_predictions.csv", index=False)

print("\nSaved: models/lightgbm_model.pkl, models/xgboost_model.json")
print("Saved: outputs/model_comparison.json, outputs/val_predictions.csv")
