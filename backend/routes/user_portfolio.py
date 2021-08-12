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
        "portfolio": [
            {
                "ticker": "BTC",
                "name": "bitcoin",
                "kind": "coin",
                "imgUrl": "aws3link",
                "amount": 10.0,
                "price": 30000,
                "apy": 300.0,
            }
        ],
    }


def historical_return(user_id: int):
    """
    get historical return for the user with user_id
    """
    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    return {
        "userId": user_id,
        "risk": 2,
        "avgApy": 30.1,
        "valueUSD": {
            "value1d": {},
            "value1w": {},
            "value1m": {},
            "value1y": {},
            "valueTotal": {},
        },
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
