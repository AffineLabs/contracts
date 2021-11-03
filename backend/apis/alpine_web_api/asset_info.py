from . import utils
import pandas as pd


def get_asset_metadata(asset_ticker: str):
    """
    Return the description of the asset with
    ticker asset_ticker
    """
    all_asset_metadata_df = utils.get_all_asset_metadata()
    if not utils.is_valid_ticker(asset_ticker, all_asset_metadata_df):
        return utils.asset_error_response(asset_ticker)
    asset_metadata = all_asset_metadata_df[
        all_asset_metadata_df["asset_ticker"] == asset_ticker.lower()
    ].iloc[
        0
    ]  # iloc[0] indexes into the only row of the dataset
    asset_metadata.where(pd.notnull(asset_metadata), None, inplace=True)

    asset_metrics_df = utils.get_asset_daily_metrics_from_sql(asset_ticker)
    asset_price_df = utils.get_asset_price_from_sql(asset_ticker)["closing_price"]
    asset_apy = utils.apy_from_prices(list(asset_price_df))
    return {
        "assetTicker": asset_ticker,
        "assetId": int(asset_metadata["asset_id"]),
        "assetFullname": asset_metadata["asset_name"],
        "assetType": asset_metadata["asset_type"],
        # "assetUrl": asset_metadata["asset_url"],
        # "assetDescription": asset_metadata["asset_description"],
        "defiSafetyScore": asset_metadata["risk_score_defi_safety"],
        "alpineRiskScore": asset_metadata["risk_score_mpl"],
        "marketCap": asset_metrics_df.iloc[-1]["market_cap"]
        if len(asset_metrics_df) > 0
        else None,
        "tradingVol24h": asset_metrics_df.iloc[-1]["trading_volume_24h"]
        if len(asset_metrics_df) > 0
        else None,
        "52WeekHigh": max(list(asset_price_df[-364:])),
        "52WeekLow": min(list(asset_price_df[-364:])),
        "apy": asset_apy,
    }


def get_historical_price(asset_ticker):
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
            zip(
                asset_price_df["timestamp"].dt.strftime("%Y-%m-%d %H:%M:%S"),
                asset_price_df["closing_price"],
            )
        ),
    }
