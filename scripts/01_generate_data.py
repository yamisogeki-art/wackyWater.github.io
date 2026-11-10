"""
Generates synthetic daily water refill demand data for Wacky Water
Delivery Refilling Station, with realistic Philippine seasonality:

- Weekly pattern: weekends and payday-adjacent days (15th/30th) spike
- Yearly pattern: dry season (Mar-May) demand rises, wet season (Jun-Nov)
  demand dips, slight December spike (holidays)
- Random daily noise + occasional supply disruption dips

Output: data/daily_transactions.csv with columns
  transaction_date, gallons_dispensed
"""

import numpy as np
import pandas as pd

np.random.seed(42)

START_DATE = "2025-06-01"
END_DATE = "2026-06-30"

dates = pd.date_range(START_DATE, END_DATE, freq="D")
n = len(dates)

BASE_DEMAND = 180  # avg gallons/day baseline

gallons = np.zeros(n)

for i, d in enumerate(dates):
    val = BASE_DEMAND

    # Weekly pattern: weekends higher (households refill before the week)
    dow = d.dayofweek  # 0=Mon
    if dow in (5, 6):  # Sat, Sun
        val *= 1.25
    elif dow == 0:  # Monday dip (people used weekend stock)
        val *= 0.9

    # Payday effect: demand spikes near the 15th and 30th
    day = d.day
    if day in (14, 15, 16, 29, 30, 1):
        val *= 1.3

    # Yearly seasonality: dry season (Mar-May) = higher demand,
    # wet season (Jun-Nov) = lower demand, Dec holiday bump
    month = d.month
    if month in (3, 4, 5):
        val *= 1.35
    elif month in (6, 7, 8, 9, 10, 11):
        val *= 0.85
    elif month == 12:
        val *= 1.15

    # Slow upward trend (business growth over the year)
    val *= (1 + 0.0003 * i)

    # Random daily noise
    val *= np.random.normal(1.0, 0.08)

    # Occasional supply disruption / low-demand outlier days (~2% of days)
    if np.random.rand() < 0.02:
        val *= np.random.uniform(0.3, 0.6)

    gallons[i] = max(val, 0)

df = pd.DataFrame({
    "transaction_date": dates,
    "gallons_dispensed": np.round(gallons, 1),
})

df.to_csv("data/daily_transactions.csv", index=False)
print(df.head(10))
print("...")
print(df.tail(5))
print(f"\nTotal rows: {len(df)}")
print(f"Mean: {df.gallons_dispensed.mean():.1f}, Std: {df.gallons_dispensed.std():.1f}")
print(f"Min: {df.gallons_dispensed.min():.1f}, Max: {df.gallons_dispensed.max():.1f}")
