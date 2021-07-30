from utils.utils import (
    is_valid_ticker,
    is_valid_user_id,
    asset_error_response,
    user_id_error_response,
)


def buy_asset(user_id, asset_ticker, amount_units):
    """
    buy asset with ticker asset_ticker
    """
    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    if not is_valid_ticker(asset_ticker):
        return asset_error_response(asset_ticker)
    return {
        "success": True,
        "transactionId": 1,
        "transactionType": "buy",
        "unitPrice": 30000,
        "amountUnits": amount_units,
        "amountUSD": 900,
        "fees": 10.0,
        "timestamp": 1626228689,
    }


def sell_asset(user_id, asset_ticker, amount_units):
    """
    sell asset with ticker asset_ticker
    """
    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    if not is_valid_ticker(asset_ticker):
        return asset_error_response(asset_ticker)

    return {
        "success": True,
        "transactionId": 1,
        "transactionType": "sell",
        "unitPrice": 30000,
        "amountUnits": amount_units,
        "amountUSD": 900,
        "fees": 10.0,
        "timestamp": 1626228689,
    }
