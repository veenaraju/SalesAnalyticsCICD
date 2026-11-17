import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

APP_ENV = os.getenv("APP_ENV", "dev").lower()

# Determine environment configuration
if APP_ENV in ("dev", "qa"):

    # In deployment, .env is alongside app.py
    DEPLOY_ENV_FILE = Path(__file__).resolve().parent / ".env"

    if DEPLOY_ENV_FILE.exists():
        env_file = DEPLOY_ENV_FILE
    else:
        # Local development fallback
        PROJECT_ROOT = Path(__file__).resolve().parents[1]
        env_file = PROJECT_ROOT / APP_ENV / ".env"

else:
    # Project-level configuration
    PROJECT_ROOT = Path(__file__).resolve().parents[1]
    env_file = PROJECT_ROOT / ".env"

load_dotenv(env_file, override=True)


def get_sales_data() -> pd.DataFrame:
    """Read sales rows from the configured database."""

    database_url = os.getenv("DATABASE_URL")

    if not database_url:
        raise ValueError(f"DATABASE_URL is missing. Environment: {APP_ENV}")

    engine = create_engine(database_url, pool_pre_ping=True)

    query = text("""
        SELECT order_id, order_date, category, product,
               quantity, unit_price
        FROM sales
        ORDER BY order_date, order_id
    """)

    with engine.connect() as connection:
        return pd.read_sql(query, connection)
