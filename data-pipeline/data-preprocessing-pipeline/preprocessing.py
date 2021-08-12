from os import listdir
from os.path import isfile, join

from sqlalchemy.sql.expression import null
import numpy as np
import pandas as pd
import s3fs
from boto3 import client
import logging

from datetime import datetime
from utils import merge_dfs, impute_data


def get_asset_filepaths(s3_bucket):
    """
    get the filepath for most recent csv data dump for each asset
    returns: a dict of {ticker : filepath to most recent csv datadump}
    """
    conn = client("s3")
    datapaths = {}
    for key in conn.list_objects(Bucket=s3_bucket)["Contents"]:
        filepath = key["Key"]
        ticker = filepath.split("/")[1].lower()
        # get all filepaths for each ticker
        datapaths[ticker] = datapaths.get(ticker, [])
        datapaths[ticker].append(filepath)

    # get the most recent filepath for each asset
    for ticker, filepaths in list(datapaths.items()):
        datapaths[ticker] = sorted(filepaths)[-1]
    return datapaths


def preprocess_coin_data(start_date, coin_data_dir, exclude_coins, s3_bucket):
    """
    return a timeseries df with all available coin prices starting
    from the start date. exclude the coins in the exclude_coins
    list
    """
    logging.info("preprocessing coin data")
    start_date = datetime.strptime(start_date, "%Y-%m-%d").date()

    # get all coin filenames
    # datafiles = [
    #     str(f)
    #     for f in listdir(coin_data_dir)
    #     if isfile(join(coin_data_dir, f)) and str(f) not in exclude_coins
    # ]
    # keep only coins
    datafiles = {
        ticker: filepath
        for ticker, filepath in get_asset_filepaths(s3_bucket).items()
        if filepath.split("/")[0] == "coin_data"
    }

    # read coin data
    logging.info("reading csv files from s3")
    coin_dfs = {
        ticker: pd.read_csv(coin_data_dir + filepath, index_col=3)
        for ticker, filepath in datafiles.items()
        if ticker not in exclude_coins
    }

    for k in list(coin_dfs.keys()):
        df = coin_dfs[k]
        # convert dates to datetime
        try:
            x_values = [
                datetime.strptime(d, "%Y-%m-%d %H:%M:%S.%f").date() for d in df.index
            ]
        except ValueError:
            x_values = [
                datetime.strptime(d, "%Y-%m-%d %H:%M:%S").date() for d in df.index
            ]
        df.index = x_values
        # if the earliest data is after start_date, skip that coin
        if min(x_values) > start_date:
            del coin_dfs[k]
        df.drop(columns=["timestamp"], inplace=True)

    # merge coin prices into one timeseries df
    coin_price_df = merge_dfs(coin_dfs, "price", take_rolling_mean=True)
    # rearrange the columns so that btc is 1st col and eth is 2nd col
    btc = coin_price_df.pop("btc")
    eth = coin_price_df.pop("eth")
    coin_price_df.insert(0, "eth", eth)
    coin_price_df.insert(0, "btc", btc)
    return coin_price_df


def preprocess_lending_data(
    start_date, lending_data_dir, exclude_protocols, coin_price_df, training_end_date
):
    """
    preprocess the lending protocol data and return the lending rates of all
    lending protocols as a timeseries
    Args:
    start_date: start date of the returning timeseries
    training_end_date  : end date of the returning timeseries
    lending_data_dir: directory of the lending data
    exclude protocols: exclude the lending protocols in this set
    coin_price_df: prices of some of the major coins. They are used to impute
                   the missing data for relatively young protocols
    Returns:
       a df of lending protocol lending returns from start_date to present

    """
    logging.info("preprocessing lending protocol data")
    filepaths = [
        str(f)
        for f in listdir(lending_data_dir)
        if isfile(join(lending_data_dir, f)) and str(f) not in exclude_protocols
    ]

    lend_protocol_dfs = {
        filepath[:-4]: pd.read_csv(lending_data_dir + filepath, index_col=0)
        for filepath in filepaths
    }

    for protocol, df in lend_protocol_dfs.items():
        x_values = [datetime.strptime(d, "%Y-%m-%d").date() for d in df.index]
        df.index = x_values
        # reverse the dataframe so that most recent data is at the tail
        lend_protocol_dfs[protocol] = df.iloc[::-1]

    # impute data
    logging.info("imputing missing data for lending protocols")
    for protocol in lend_protocol_dfs.keys():
        X = coin_price_df
        y = lend_protocol_dfs[protocol][["lend_rate"]]
        lend_protocol_dfs[protocol] = impute_data(X, y, start_date, training_end_date)

    lend_rates_df = merge_dfs(lend_protocol_dfs, "lend_rate", take_rolling_mean=True)
    lend_rates_df["nexo"] = 12.0  # usdc, usdt
    lend_rates_df["celsius"] = 8.8  # usdc, usdt

    # start with $1, and apply daily yield each day to convert
    # lend rates to lending protocol (lp) returns
    lp_returns = {protocol: [1.0] for protocol in lend_rates_df.columns}
    for i, _ in enumerate(lend_rates_df.index[:-1]):
        for protocol, returns in lp_returns.items():
            daily_yield = (1 + lend_rates_df[protocol][i] / 100) ** (1 / 365) - 1
            returns.append(returns[-1] * (1 + daily_yield))
    lp_returns_df = pd.DataFrame(lp_returns, index=lend_rates_df.index)
    return lp_returns_df


def read_asset_metadata(args, asset_types):
    """
    read the asset_metadata
    args:        main function args
    asset_types: a dict from asset name to asset type
    """
    asset_metadata_df = pd.read_csv(
        args.data_dir + "clean_data/asset_metadata.csv", index_col=0
    )
    # keep only the metadata about the assets for which we have price data
    asset_metadata_df = asset_metadata_df[
        asset_metadata_df["Ticker"].isin(set(asset_types.keys()))
    ]

    asset_metadata_df.rename(
        columns={"Name": "asset_name", "Ticker": "asset_ticker"}, inplace=True
    )
    # create a unique id for each asset
    asset_metadata_df["asset_id"] = range(len(asset_metadata_df))
    asset_metadata_df["asset_type"] = [
        asset_types[asset_ticker] for asset_ticker in asset_metadata_df["asset_ticker"]
    ]
    asset_metadata_df["asset_img_url"] = "placeholder"
    asset_metadata_df["asset_url"] = "placeholder"
    asset_metadata_df["asset_description"] = "placeholder"
    asset_metadata_df["risk_score_defi_safety"] = None
    asset_metadata_df["risk_score_mpl"] = None
    asset_metadata_df["risk_assesment"] = [["placeholder", "placeholder"]] * len(
        asset_metadata_df
    )

    # delete the columns that we don't use
    del asset_metadata_df["Last Price"]
    del asset_metadata_df["Change"]
    del asset_metadata_df["Pcnt Change"]
    del asset_metadata_df["Volume in Currencies (24Hr)"]
    del asset_metadata_df["Circulating Supply"]
    return asset_metadata_df


def read_asset_price_and_metadata(args):
    # first read the data from the csv files
    coin_price_df = preprocess_coin_data(
        args.start_date,
        args.s3_data_dir,
        args.exclude_coins,
        args.s3_bucket,
    )

    lending_return_df = preprocess_lending_data(
        args.start_date,
        args.data_dir + "lending_data/",
        args.exclude_protocols,
        coin_price_df,
        args.training_end_date,
    )

    asset_price_df = pd.merge(
        coin_price_df, lending_return_df, left_index=True, right_index=True, how="inner"
    )

    # create asset types for all assets
    asset_types = {
        asset_ticker: (
            "coin" if asset_ticker in coin_price_df.columns else "lending_protocol"
        )
        for asset_ticker in asset_price_df.columns
    }
    asset_metadata_df = read_asset_metadata(args, asset_types)
    return asset_price_df, asset_metadata_df
