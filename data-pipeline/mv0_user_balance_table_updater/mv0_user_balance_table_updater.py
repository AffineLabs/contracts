import pandas as pd
import logging
import sqlalchemy
import sys
import os

sys.path.append("..")
from portfolio_creation_pipeline import generate_returns, constant

if __name__ == "__main__":
    logging.info("updating user balance table for mv0")
    engine = sqlalchemy.create_engine(os.environ.get("POSTGRES_REMOTE_URL"))
    asset_price_long_df = pd.read_sql_table("asset_price", engine)
    # convert data from long to wide format
    asset_prices_df = asset_price_long_df.pivot(
        index="timestamp", columns="asset_ticker", values="closing_price"
    )

    asset_ticker_to_asset_id = dict(
        zip(asset_price_long_df["asset_ticker"], asset_price_long_df["asset_id"])
    )
    investment_daily_value_df = generate_returns.get_daily_value_of_asset_portfolios(
        constant.asset_level_portfolios, asset_prices_df
    )

    output_json = {}
    # user_asset_weights is the weight of different asset level portfolios in user portfolio
    # this changes as the underlying asset_prices_change
    (
        user_investment_daily_value,
        user_roi,
    ) = generate_returns.generate_daily_value_and_roi(
        constant.user_asset_allocations[f"risk1"],
        investment_daily_value_df,
        rebalance_period=90,
    )
    # assuming user follows risk 1 strategy (80% alpSave, 20% btc-eth)
    user_balance_df = pd.DataFrame(
        {
            # in mv0, we have one user, and their user id is 1
            "user_id": [1] * len(investment_daily_value_df),
            "user_public_address": ["0xfakeaddr"] * len(investment_daily_value_df),
            "tick_size": ["1d"] * len(investment_daily_value_df),
            "timestamp": investment_daily_value_df.index,
            "user_balance": user_investment_daily_value
            * 100,  # assuming init investment of 10k.
        }
    )

    user_balance_df.set_index(["user_id", "tick_size", "timestamp"], inplace=True)

    with engine.connect() as con:
        con.execute("DELETE FROM user_balance;")
    user_balance_df.to_sql("user_balance", con=engine, if_exists="append")
