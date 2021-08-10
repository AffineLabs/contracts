import pandas as pd
from sqlalchemy import create_engine
import os

engine = create_engine(os.environ.get("POSTGRES_REMOTE_URL"))


def get_all_asset_metadata():
    return pd.read_sql_table("asset_metadata", engine)


def is_valid_ticker(asset_ticker: str, asset_metadata_df: pd.DataFrame):
    return asset_ticker.lower() in set(asset_metadata_df["asset_ticker"])


def is_valid_user_id(user_id: int):
    return True


def asset_error_response(asset_ticker: str):
    return {"assetTicker": asset_ticker, "message": "Not a valid asset ticker!"}


def user_id_error_response(user_id: int):
    return {"userId": user_id, "message": "Not a valid user id!"}


def get_asset_price_from_sql(asset_ticker):
    asset_price_df = pd.read_sql_query(
        f"""
        SELECT * 
          FROM asset_price 
         WHERE asset_ticker = '{asset_ticker}';
        """,
        engine,
    )
    return asset_price_df


def calculate_asset_historical_return(
    asset_ticker, asset_price_df, period=None, full_data=False
):
    """
    return at most ndatapoints evenly spaced data points from the period (in days)
    """
    if full_data:  # return all data points in this period
        dates = asset_price_df["timestamp"]
        asset_prices = asset_price_df["closing_price"]
    else:  # return ndatapoints
        ndatapoints = 50
        interval = 1
        if period is None:
            period = len(asset_price_df)
            interval = period // ndatapoints
        elif period > ndatapoints and period <= 2 * ndatapoints:
            period = ndatapoints
        elif period > 2 * ndatapoints:
            interval = period // ndatapoints
        dates = asset_price_df["timestamp"][-period::interval]
        asset_prices = asset_price_df["closing_price"][-period::interval]
    return dict(zip(dates, asset_prices))
