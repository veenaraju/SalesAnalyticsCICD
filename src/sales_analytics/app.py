from pathlib import Path

import plotly.express as px
import streamlit as st
from dotenv import load_dotenv

from sales_analytics.analytics import (
    calculate_kpis,
    category_sales,
    monthly_sales,
    prepare_sales_data,
)
from sales_analytics.database import get_sales_data


def main() -> None:
    load_dotenv(Path.cwd() / ".env", override=True)

    st.set_page_config(page_title="Sales Analytics Updated", layout="wide")
    st.title("Sales Analytics Dashboard")
    st.caption("Local CI/CD demonstration | Streamlit + Python + MySQL")

    try:
        raw_df = get_sales_data()
        if raw_df.empty:
            st.warning("No sales records were found in the configured database.")
            st.stop()

        df = prepare_sales_data(raw_df)
        kpis = calculate_kpis(df)

        col1, col2, col3 = st.columns(3)
        col1.metric("Total Sales", f"₹{kpis['total_sales']:,.2f}")
        col2.metric("Orders", f"{kpis['orders']:,}")
        col3.metric("Average Order Value", f"₹{kpis['average_order_value']:,.2f}")

        left, right = st.columns(2)
        with left:
            st.subheader("Monthly Sales")
            st.plotly_chart(
                px.line(
                    monthly_sales(df),
                    x="month",
                    y="sales_amount",
                    markers=True,
                    title="Sales by Month",
                ),
                use_container_width=True,
            )
        with right:
            st.subheader("Sales by Category")
            st.plotly_chart(
                px.bar(
                    category_sales(df),
                    x="category",
                    y="sales_amount",
                    title="Sales by Category",
                ),
                use_container_width=True,
            )

        st.subheader("Sales Transactions")
        st.dataframe(df, use_container_width=True)
    except Exception as exc:
        st.error(f"Unable to load the dashboard: {exc}")
        st.info("Check the .env database connection and confirm that MySQL is running.")


if __name__ == "__main__":
    main()
