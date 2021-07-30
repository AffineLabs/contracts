from utils.utils import (
    is_valid_ticker,
    is_valid_user_id,
    asset_error_response,
    user_id_error_response,
    get_asset_historical_return,
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
    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    if not is_valid_ticker(asset_ticker):
        return asset_error_response(asset_ticker)

    return {
        "userId": user_id,
        "assetTicker": asset_ticker,
        "assetTotalVal": 1000.10,
        "assetUnitCount": 2,
        "portfolioPercentage": 20.0,
        "unitPrice": {
            "price1d": get_asset_historical_return(asset_ticker, 1),
            "price1w": get_asset_historical_return(asset_ticker, 7),
            "price1m": get_asset_historical_return(asset_ticker, 30),
            "price1y": get_asset_historical_return(asset_ticker, 365),
            "priceTotal": get_asset_historical_return(asset_ticker),
        },
        "avgCost": 100.0,
        "avgApy": 10.0,
        "percentageFee": 0.015,
    }
