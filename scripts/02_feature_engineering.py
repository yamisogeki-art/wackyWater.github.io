"""
Turns the raw daily_transactions series into a tabular feature set
suitable for LightGBM/XGBoost (as opposed to the sequence-window input
an LSTM would use).

Features:
  - lag_1, lag_7, lag_14         : demand N days ago
  - rolling_mean_7, rolling_std_7: 7-day rolling stats (excl. current day)
  - rolling_mean_14              : 14-day rolling mean
  - day_of_week, month, day      : calendar signals
  - is_weekend                   : Sat/Sun flag
  - is_payday_window             : near 15th/30th (PH payday demand spikes)
  - is_dry_season                : Mar-May flag (PH dry season = higher demand)

Target:
  - gallons_dispensed (next-day demand, i.e. the row's own value,
    predicted from the PRIOR days' features)

Output: data/features.csv
"""

import numpy as np
import pandas as pd

df = pd.read_csv("data/daily_transactions.csv",
                  parse_dates=["transaction_date"])
df = df.sort_values("transaction_date").reset_index(drop=True)

# Lag features
df["lag_1"] = df["gallons_dispensed"].shift(1)
df["lag_7"] = df["gallons_dispensed"].shift(7)
df["lag_14"] = df["gallons_dispensed"].shift(14)

# Rolling stats computed on PRIOR days only (shift(1) before rolling
# avoids leaking the current day's value into its own features)
df["rolling_mean_7"] = df["gallons_dispensed"].shift(1).rolling(7).mean()
df["rolling_std_7"] = df["gallons_dispensed"].shift(1).rolling(7).std()
df["rolling_mean_14"] = df["gallons_dispensed"].shift(1).rolling(14).mean()

# Calendar features
df["day_of_week"] = df["transaction_date"].dt.dayofweek
df["month"] = df["transaction_date"].dt.month
df["day"] = df["transaction_date"].dt.day
df["is_weekend"] = df["day_of_week"].isin([5, 6]).astype(int)
df["is_payday_window"] = df["day"].isin([14, 15, 16, 29, 30, 1]).astype(int)
df["is_dry_season"] = df["month"].isin([3, 4, 5]).astype(int)

# Drop rows with NaNs introduced by lag/rolling windows (first 14 days)
before = len(df)
df_clean = df.dropna().reset_index(drop=True)
print(f"Dropped {before - len(df_clean)} warm-up rows (need 14 days of history)")

df_clean.to_csv("data/features.csv", index=False)
print(f"\nFeature set: {df_clean.shape[0]} rows x {df_clean.shape[1]} columns")
print(df_clean.columns.tolist())
print(df_clean.head(3))
