import pandas as pd
import sqlalchemy
import os

engine = sqlalchemy.create_engine(os.environ.get("POSTGRES_REMOTE_URL"))


def get_all_asset_metadata():
    return pd.read_sql_table("asset_metadata", engine)


def is_valid_ticker(asset_ticker: str, asset_metadata_df: pd.DataFrame):
    return asset_ticker.lower() in set(asset_metadata_df["asset_ticker"])


def is_valid_user_id(user_id: int):
    return user_id == 1


def asset_error_response(asset_ticker: str):
    return {"assetTicker": asset_ticker, "message": "Invalid asset ticker!"}


def user_id_error_response(user_id: int):
    return {"userId": user_id, "message": "Invalid user id!"}


def get_asset_price_from_sql(asset_ticker: str):
    asset_price_df = pd.read_sql_query(
        f"""
        SELECT * 
          FROM asset_price 
         WHERE asset_ticker = '{asset_ticker}';
        """,
        engine,
    )
    return asset_price_df


def get_user_balance_from_sql(user_id: int):
    user_balance_df = pd.read_sql_query(
        f"""
        SELECT * 
          FROM user_balance 
         WHERE user_id = {user_id};
        """,
        engine,
    )
    return user_balance_df


def get_asset_daily_metrics_from_sql(asset_ticker: str):
    asset_daily_metrics_df = pd.read_sql_query(
        f"""
        SELECT * 
          FROM asset_daily_metrics 
         WHERE asset_ticker = '{asset_ticker}';
        """,
        engine,
    )
    return asset_daily_metrics_df


def apy_from_prices(asset_prices):
    start_price, end_price = asset_prices[0], asset_prices[-1]
    period_length = len(asset_prices)
    # source: https://en.wikipedia.org/wiki/Annual_percentage_yield
    apy = 100 * ((end_price / start_price) ** (365 / period_length) - 1)
    return apy
