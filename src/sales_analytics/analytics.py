import pandas as pd


def prepare_sales_data(df: pd.DataFrame) -> pd.DataFrame:
    """Prepare transaction data and calculate the net sales amount."""
    result = df.copy()
    result["order_date"] = pd.to_datetime(result["order_date"])
    result["sales_amount"] = result["quantity"] * result["unit_price"]
    result["month"] = result["order_date"].dt.to_period("M").astype(str)
    return result


def calculate_kpis(df: pd.DataFrame) -> dict:
    """Return total sales, distinct orders, and average order value."""
    total_sales = float(df["sales_amount"].sum())
    orders = int(df["order_id"].nunique())
    average_order_value = total_sales / orders if orders else 0.0
    return {
        "total_sales": total_sales,
        "orders": orders,
        "average_order_value": average_order_value,
    }


def monthly_sales(df: pd.DataFrame) -> pd.DataFrame:
    """Aggregate sales by calendar month."""
    return (
        df.groupby("month", as_index=False)["sales_amount"]
        .sum()
        .sort_values("month")
    )


def category_sales(df: pd.DataFrame) -> pd.DataFrame:
    """Aggregate sales by product category."""
    return (
        df.groupby("category", as_index=False)["sales_amount"]
        .sum()
        .sort_values("category")
    )
