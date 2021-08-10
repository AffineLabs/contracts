from utils.utils import (
    is_valid_ticker,
    asset_error_response,
    calculate_asset_historical_return,
    get_all_asset_metadata,
    get_asset_price_from_sql,
)


def asset_description(asset_ticker: str):
    """
    Return the description of the asset with
    ticker asset_ticker
    """
    asset_metadata_df = get_all_asset_metadata()
    if not is_valid_ticker(asset_ticker, asset_metadata_df):
        return asset_error_response(asset_ticker)
    asset_metadata_df = asset_metadata_df[
        asset_metadata_df["asset_ticker"] == asset_ticker.lower()
    ]
    asset_price_df = get_asset_price_from_sql(asset_ticker)
    return {
        "assetTicker": asset_ticker,
        "assetFullname": asset_metadata_df["asset_name"][0],
        "shortDescription": "to the moon!",
        "riskInfo": ["", ""],
        "defiScore": None,
        "defiSafetyScore": None,
        "marketCap": None,
        "dilutedCap": None,
        "low52wk": min(
            calculate_asset_historical_return(
                asset_ticker, asset_price_df, 365, full_data=True
            ).values()
        ),
        "high52wk": max(
            calculate_asset_historical_return(
                asset_ticker, asset_price_df, 365, full_data=True
            ).values()
        ),
        "cvarHistorgram": [],
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
    }


def historical_return(asset_ticker):
    """
    return the historical return of the
    asset with ticker asset ticker
    """
    asset_price_df = get_asset_price_from_sql(asset_ticker)
    return {
        "assetTicker": asset_ticker,
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
    }
