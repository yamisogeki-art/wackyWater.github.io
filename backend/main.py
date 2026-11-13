"""
FastAPI backend for WackySmart demand forecasting (Production Ready).

Run locally:
    pip install -r requirements.txt
    export SUPABASE_URL="https://xxxx.supabase.co"
    export SUPABASE_SERVICE_KEY="your-service-role-key"
    export API_SECRET_KEY="wackysmart_secret_key_2025"
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Production Deploy (Render / Railway / Fly.io / Cloud VM):
    Set environment variables in your cloud host dashboard.
    Enforces HTTPS, API Key authentication, restricted CORS, and disabled docs in production.
"""

import os
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Dict, Optional

import joblib
import numpy as np
import pandas as pd
from fastapi import FastAPI, HTTPException, Header, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client

# Environment configuration
ENV = os.environ.get("ENV", "development").lower()
IS_PROD = ENV in ("production", "prod")
API_SECRET_KEY = os.environ.get("API_SECRET_KEY", "wackysmart_secret_key_2025")
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://hsrsuuyqqtyqeutcvorp.supabase.co")
SUPABASE_SERVICE_KEY = os.environ.get(
    "SUPABASE_SERVICE_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhzcnN1dXlxcXR5cWV1dGN2b3JwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwODQ4NzcsImV4cCI6MjEwMzY2MDg3N30.4S81Zzktm9RTD_HvqWT8LXXdBrtK4Znt3sa60uvLGYc"
)

# Global loaded model in-memory storage
ml_model = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Preloads the LightGBM model into memory at server startup to prevent cold-start delays."""
    global ml_model
    possible_paths = [
        os.path.join(os.path.dirname(__file__), "..", "models", "lightgbm_model.pkl"),
        os.path.join(os.path.dirname(__file__), "lightgbm_model.pkl"),
        "/app/models/lightgbm_model.pkl",
    ]

    model_path = None
    for p in possible_paths:
        if os.path.exists(p):
            model_path = p
            break

    try:
        if model_path:
            ml_model = joblib.load(model_path)
            print(f"✅ LightGBM model preloaded into memory from {model_path}")
        else:
            print("⚠️ Warning: Model file not found. Server will start, but /forecast requires model file.")
    except Exception as e:
        print(f"❌ Error loading LightGBM model: {e}")
    yield
    ml_model = None

# Hide Swagger/OpenAPI docs in production for security
app = FastAPI(
    title="WackySmart Demand Forecasting API",
    version="1.0.0",
    docs_url=None if IS_PROD else "/docs",
    redoc_url=None if IS_PROD else "/redoc",
    openapi_url=None if IS_PROD else "/openapi.json",
    lifespan=lifespan,
)

# CORS Lockdown
allowed_origins_env = os.environ.get("ALLOWED_ORIGINS", "")
allowed_origins = [o.strip() for o in allowed_origins_env.split(",") if o.strip()]
if not allowed_origins:
    if IS_PROD:
        allowed_origins = ["https://musical-arithmetic-dbdd3b.netlify.app"]
    else:
        allowed_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Rate Limiting (15 requests per minute per IP)
RATE_LIMIT_WINDOW = 60
MAX_REQUESTS_PER_WINDOW = 15
request_counts: Dict[str, list] = {}

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    client_ip = request.client.host if request.client else "unknown"
    now = time.time()

    timestamps = [t for t in request_counts.get(client_ip, []) if now - t < RATE_LIMIT_WINDOW]
    if len(timestamps) >= MAX_REQUESTS_PER_WINDOW:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Please wait a minute before requesting another forecast.",
        )

    timestamps.append(now)
    request_counts[client_ip] = timestamps
    return await call_next(request)

# API Key Authentication Header verification
def verify_api_key(
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
    authorization: Optional[str] = Header(None),
):
    """Validates X-API-Key or Authorization Bearer header against configured API_SECRET_KEY."""
    if not API_SECRET_KEY:
        return True

    token = x_api_key
    if not token and authorization:
        if authorization.lower().startswith("bearer "):
            token = authorization[7:].strip()
        else:
            token = authorization.strip()

    if token != API_SECRET_KEY:
        raise HTTPException(
            status_code=401,
            detail="Unauthorized: Missing or invalid API key header (X-API-Key).",
        )
    return True

# Supabase Client Initialization
_supabase_client = None

def get_supabase():
    global _supabase_client
    if _supabase_client is None:
        if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
            raise HTTPException(
                status_code=500,
                detail="SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables are not configured on server.",
            )
        _supabase_client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    return _supabase_client

FEATURE_COLS = [
    "lag_1", "lag_7", "lag_14",
    "rolling_mean_7", "rolling_std_7", "rolling_mean_14",
    "day_of_week", "month", "day",
    "is_weekend", "is_payday_window", "is_dry_season",
]

def build_features(history: pd.DataFrame, target_date: pd.Timestamp) -> dict:
    series = history.set_index("transaction_date")["gallons_dispensed"]

    lag_1 = float(series.iloc[-1])
    lag_7 = float(series.iloc[-7])
    lag_14 = float(series.iloc[-14])
    rolling_mean_7 = float(series.iloc[-7:].mean())
    rolling_std_7 = float(series.iloc[-7:].std())
    rolling_mean_14 = float(series.iloc[-14:].mean())

    return {
        "lag_1": lag_1,
        "lag_7": lag_7,
        "lag_14": lag_14,
        "rolling_mean_7": rolling_mean_7,
        "rolling_std_7": rolling_std_7,
        "rolling_mean_14": rolling_mean_14,
        "day_of_week": target_date.dayofweek,
        "month": target_date.month,
        "day": target_date.day,
        "is_weekend": int(target_date.dayofweek in (5, 6)),
        "is_payday_window": int(target_date.day in (14, 15, 16, 29, 30, 1)),
        "is_dry_season": int(target_date.month in (3, 4, 5)),
    }

@app.get("/")
def health_check():
    return {
        "status": "ok",
        "env": ENV,
        "model_loaded": ml_model is not None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

@app.get("/forecast")
@app.post("/forecast")
def forecast(authenticated: bool = Depends(verify_api_key)):
    if ml_model is None:
        raise HTTPException(
            status_code=500,
            detail="LightGBM model is not loaded in memory on the server.",
        )

    supabase = get_supabase()

    # Pull recent transactions from Supabase
    response = (
        supabase.table("daily_transactions")
        .select("transaction_date, gallons_dispensed")
        .order("transaction_date", desc=True)
        .limit(21)
        .execute()
    )
    rows = response.data
    if len(rows) < 14:
        raise HTTPException(
            status_code=400,
            detail=f"Need at least 14 days of transaction history, found {len(rows)}.",
        )

    history = pd.DataFrame(rows)
    history["transaction_date"] = pd.to_datetime(history["transaction_date"])
    history = history.sort_values("transaction_date").reset_index(drop=True)

    last_date = history["transaction_date"].iloc[-1]
    target_date = last_date + timedelta(days=1)

    features = build_features(history, target_date)
    X = pd.DataFrame([features])[FEATURE_COLS]

    predicted_gallons = float(ml_model.predict(X)[0])

    record = {
        "forecast_date": target_date.date().isoformat(),
        "predicted_gallons": round(predicted_gallons, 1),
        "model_version": "lightgbm_v1",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    supabase.table("forecasts").insert(record).execute()

    return record
