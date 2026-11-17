import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

PROJECT_ROOT = Path(__file__).resolve().parents[1]

APP_ENV = os.getenv("APP_ENV", "dev")

if APP_ENV == "dev":
    env_file = PROJECT_ROOT / "dev" / ".env"
elif APP_ENV == "qa":
    env_file = PROJECT_ROOT / "qa" / ".env"
else:
    env_file = PROJECT_ROOT / ".env"

load_dotenv(env_file, override=True)


def get_sales_data() -> pd.DataFrame:
    database_url = os.getenv("DATABASE_URL")

    if not database_url:
        raise ValueError("DATABASE_URL is missing.")

    engine = create_engine(database_url, pool_pre_ping=True)

    query = text("""
        SELECT order_id, order_date, category, product,
               quantity, unit_price
        FROM sales
        ORDER BY order_date, order_id
    """)

    with engine.connect() as connection:
        return pd.read_sql(query, connection)
