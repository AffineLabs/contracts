import pandas as pd

data_path = "../notebook/data/clean_data/"


def get_all_asset_info():
    return pd.read_csv(data_path + "asset_info.csv")


def is_valid_ticker(asset_ticker: str):
    asset_info_df = get_all_asset_info()
    return asset_ticker.lower() in set(asset_info_df["Ticker"])


def is_valid_user_id(user_id: int):
    return True


def asset_error_response(asset_ticker: str):
    return {"assetTicker": asset_ticker, "message": "Not a valid asset ticker!"}


def user_id_error_response(user_id: int):
    return {"userId": user_id, "message": "Not a valid user id!"}


def get_asset_historical_return(asset_ticker, period=None, full_data=False):
    """
    return at most ndatapoints evenly spaced data points from the period (in days)
    """
    if not is_valid_ticker(asset_ticker):
        return asset_error_response(asset_ticker)

    assets_df = pd.read_csv(data_path + "asset_prices_2021-07-08.csv", index_col=0)
    asset_info_df = pd.read_csv(data_path + "asset_info.csv")
    asset_name = asset_info_df[asset_info_df["Ticker"] == asset_ticker.lower()]["Name"]
    asset_name = list(asset_name)[0]

    if full_data:  # return all data points in this period
        dates = assets_df.index
        asset_prices = assets_df[asset_name]
    else:  # return ndatapoints
        ndatapoints = 50
        interval = 1
        if period is None:
            period = len(assets_df)
            interval = period // ndatapoints
        elif period > ndatapoints and period <= 2 * ndatapoints:
            period = ndatapoints
        elif period > 2 * ndatapoints:
            interval = period // ndatapoints
        dates = assets_df.index[-period::interval]
        asset_prices = assets_df[asset_name][-period::interval]
    return dict(zip(dates, asset_prices))
