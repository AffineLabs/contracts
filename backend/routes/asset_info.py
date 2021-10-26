from utils import utils


def asset_description(asset_ticker: str):
    """
    Return the description of the asset with
    ticker asset_ticker
    """
    all_asset_metadata_df = utils.get_all_asset_metadata()
    if not utils.is_valid_ticker(asset_ticker, all_asset_metadata_df):
        return utils.asset_error_response(asset_ticker)
    asset_metadata = all_asset_metadata_df.loc[
        all_asset_metadata_df["asset_ticker"] == asset_ticker.lower()
    ]
    asset_daily_metrics_df = utils.get_asset_daily_metrics(asset_ticker)
    asset_price_52wk = utils.get_asset_price_from_sql(asset_ticker)["closing_price"][
        -364:
    ]

    return {
        "assetTicker": asset_ticker,
        "assetId": asset_metadata["asset_id"][0],
        "assetFullname": asset_metadata["asset_name"][0],
        "marketCap": asset_daily_metrics_df["market_cap"][-1],
        "tradingVol24h": asset_daily_metrics_df["trading_volume_24h"][-1],
        "52WeekHigh": max(asset_price_52wk),
        "52WeekLow": min(asset_price_52wk),
    }


def historical_return(asset_ticker):
    """
    return the historical return of the
    asset with ticker asset ticker
    """
    all_asset_metadata_df = utils.get_all_asset_metadata()
    if not utils.is_valid_ticker(asset_ticker, all_asset_metadata_df):
        return utils.asset_error_response(asset_ticker)
    asset_price_df = utils.get_asset_price_from_sql(asset_ticker)
    return {
        "assetTicker": asset_ticker,
        "historicalPrice": dict(
            zip(asset_price_df["timestamp"], asset_price_df["closing_price"])
        ),
    }
