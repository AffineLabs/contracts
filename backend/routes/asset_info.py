from utils.utils import (
    is_valid_ticker,
    asset_error_response,
    get_asset_historical_return,
    get_all_asset_info,
)


def asset_description(asset_ticker: str):
    """
    Return the description of the asset with
    ticker asset_ticker
    """
    if not is_valid_ticker(asset_ticker):
        return asset_error_response(asset_ticker)
    asset_info_df = get_all_asset_info()
    asset_info_df = asset_info_df[asset_info_df["Ticker"] == asset_ticker.lower()]
    return {
        "assetTicker": asset_ticker,
        "assetFullname": asset_info_df["Name"][0],
        "shortDescription": "to the moon!",
        "riskInfo": ["", ""],
        "defiScore": None,
        "defiSafetyScore": None,
        "marketCap": asset_info_df["Market Cap"][0],
        "dilutedCap": None,
        "low52wk": min(
            get_asset_historical_return(asset_ticker, 365, full_data=True).values()
        ),
        "high52wk": max(
            get_asset_historical_return(asset_ticker, 365, full_data=True).values()
        ),
        "cvarHistorgram": [],
        "unitPrice": {
            "price1d": get_asset_historical_return(asset_ticker, 1),
            "price1w": get_asset_historical_return(asset_ticker, 7),
            "price1m": get_asset_historical_return(asset_ticker, 30),
            "price1y": get_asset_historical_return(asset_ticker, 365),
            "priceTotal": get_asset_historical_return(asset_ticker),
        },
    }


def historical_return(asset_ticker):
    """
    return the historical return of the
    asset with ticker asset ticker
    """
    if not is_valid_ticker(asset_ticker):
        return asset_error_response(asset_ticker)
    return {
        "assetTicker": asset_ticker,
        "unitPrice": {
            "price1d": get_asset_historical_return(asset_ticker, 1),
            "price1w": get_asset_historical_return(asset_ticker, 7),
            "price1m": get_asset_historical_return(asset_ticker, 30),
            "price1y": get_asset_historical_return(asset_ticker, 365),
            "priceTotal": get_asset_historical_return(asset_ticker),
        },
    }
