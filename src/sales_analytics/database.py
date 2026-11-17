import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text


def get_sales_data() -> pd.DataFrame:
    """Read sales rows from the configured database."""
    load_dotenv(Path.cwd() / ".env", override=True)

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise ValueError("DATABASE_URL is missing in .env")

    engine = create_engine(database_url, pool_pre_ping=True)
    query = text("""
        SELECT order_id, order_date, category, product,
               quantity, unit_price
        FROM sales
        ORDER BY order_date, order_id
    """)

    with engine.connect() as connection:
        return pd.read_sql(query, connection)
