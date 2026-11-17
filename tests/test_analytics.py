import pandas as pd

from sales_analytics.analytics import (
    calculate_kpis,
    category_sales,
    monthly_sales,
    prepare_sales_data,
)


def sample_data() -> pd.DataFrame:
    return pd.DataFrame(
        {
            "order_id": [1, 2, 3],
            "order_date": ["2026-01-05", "2026-01-10", "2026-02-02"],
            "category": ["Electronics", "Furniture", "Electronics"],
            "product": ["Laptop", "Chair", "Mobile"],
            "quantity": [2, 5, 3],
            "unit_price": [1000, 500, 2000],
        }
    )


def test_sales_calculation():
    result = prepare_sales_data(sample_data())
    assert result["sales_amount"].tolist() == [2000, 2500, 6000]


def test_kpis():
    result = prepare_sales_data(sample_data())
    kpis = calculate_kpis(result)
    assert kpis["total_sales"] == 10500
    assert kpis["orders"] == 3
    assert kpis["average_order_value"] == 3500


def test_monthly_sales():
    result = prepare_sales_data(sample_data())
    monthly = monthly_sales(result)
    assert monthly["sales_amount"].tolist() == [4500, 6000]


def test_category_sales_total():
    result = prepare_sales_data(sample_data())
    categories = category_sales(result)
    assert categories["sales_amount"].sum() == 10500
