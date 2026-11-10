import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv("outputs/val_predictions.csv",
                  parse_dates=["transaction_date"])

fig, ax = plt.subplots(figsize=(10, 5))
ax.plot(df["transaction_date"], df["gallons_dispensed"], label="Actual", color="#2C2C2A", linewidth=2, marker="o", markersize=3)
ax.plot(df["transaction_date"], df["lightgbm_pred"], label="LightGBM prediction", color="#0F6E56", linewidth=1.5, linestyle="--")
ax.plot(df["transaction_date"], df["xgboost_pred"], label="XGBoost prediction", color="#993C1D", linewidth=1.5, linestyle="--")

ax.set_title("Daily gallons demand: actual vs. predicted (June 2026 validation)")
ax.set_xlabel("Date")
ax.set_ylabel("Gallons dispensed")
ax.legend()
ax.grid(alpha=0.3)
fig.autofmt_xdate()
plt.tight_layout()
plt.savefig("outputs/model_comparison_chart.png", dpi=150)
print("Saved chart to outputs/model_comparison_chart.png")
