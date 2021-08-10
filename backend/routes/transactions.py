from typing import List

from utils.utils import (
    is_valid_ticker,
    is_valid_user_id,
    asset_error_response,
    user_id_error_response,
    get_all_asset_metadata,
)


def user_transactions(user_id: int, asset_tickers: List):
    if not is_valid_user_id(user_id):
        return user_id_error_response(user_id)

    transaction_history = {}
    asset_metadata_df = get_all_asset_metadata()
    if len(asset_tickers) == 1 and asset_tickers[0] == "all":
        asset_tickers = asset_metadata_df["asset_ticker"]
    for asset_ticker in asset_tickers:
        if not is_valid_ticker(asset_ticker, asset_metadata_df):
            return asset_error_response(asset_ticker)
        transaction_history[asset_ticker] = [
            {
                "transactionId": 1,
                "transactionType": "buy",
                "unitPrice": 30000,
                "amountUnits": 0.03,
                "amountUSD": 900,
                "fees": 10.0,
                "timestamp": 1626228689,
            },
            {
                "transactionId": 12,
                "transactionType": "sell",
                "unitPrice": 35000,
                "amountUnits": 0.1,
                "amountUSD": 350,
                "fees": 10.0,
                "timestamp": 1626228691,
            },
        ]

    return transaction_history
