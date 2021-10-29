from typing import List
import utils


def user_transactions(user_id: int, asset_tickers: List):
    if not utils.is_valid_user_id(user_id):
        return utils.user_id_error_response(user_id)

    transaction_history = {}
    asset_metadata_df = utils.get_all_asset_metadata()
    if len(asset_tickers) == 1 and asset_tickers[0] == "all":
        asset_tickers = asset_metadata_df["asset_ticker"]
    for asset_ticker in asset_tickers:
        if not utils.is_valid_ticker(asset_ticker, asset_metadata_df):
            return utils.asset_error_response(asset_ticker)
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


def withdraw(user_id: int):
    return "User has now withdrawn all funds"
