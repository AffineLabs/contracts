from datetime import datetime, timedelta
import random

from utils.utils import (
    is_valid_ticker,
    is_valid_user_id,
    asset_error_response,
    user_id_error_response,
    get_asset_price_from_sql,
    calculate_asset_historical_return,
    get_all_asset_metadata,
)


def user_portfolio(user_id: int):
    """
    return the current portfolio of the user user_id
    """
    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    return {
        "userId": user_id,
        "userAddress": "0xfakeAddr",
        "portfolio": {
            "mCash": {"amount": 1200, "price": 1.2},
            "mLarge": {"amount": 3.1, "price": 27_000},
            "mAlt": {"amount": 5, "price": 5}
        }
    }


def historical_balance(user_id: int):
    """
    get historical return for the user with user_id
    """
    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    now = datetime.utcnow()
    dates = [now - timedelta(days=num) for num in range(365)]
    date_strs = [date.strftime("%Y-%m-%d") for date in dates]
    # rando balances per day
    balances = [random.randint(10, int(1e6)) for num in range(len(date_strs))]
    date_balances = {date: bal for date, bal in zip(date_strs, balances)}
    return {
        "userId": user_id,
        "historical_balances": date_balances
        }


def user_asset_info(user_id: int, asset_ticker: str):
    """
    return info about user's holdings of the asset
    """
    asset_metadata_df = get_all_asset_metadata()

    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    if not is_valid_ticker(asset_ticker, asset_metadata_df):
        return asset_error_response(asset_ticker)

    asset_price_df = get_asset_price_from_sql(asset_ticker)
    return {
        "userId": user_id,
        "assetTicker": asset_ticker,
        "assetTotalVal": 1000.10,
        "assetUnitCount": 2,
        "portfolioPercentage": 20.0,
        "unitPrice": {
            "price1w": calculate_asset_historical_return(
                asset_ticker, asset_price_df, 7
            ),
            "price1m": calculate_asset_historical_return(
                asset_ticker, asset_price_df, 30
            ),
            "price1y": calculate_asset_historical_return(
                asset_ticker, asset_price_df, 365
            ),
            "priceTotal": calculate_asset_historical_return(
                asset_ticker, asset_price_df
            ),
        },
        "avgCost": 100.0,
        "avgApy": 10.0,
        "percentageFee": 0.015,
    }
