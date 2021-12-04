from os import listdir
from os.path import isfile, join

import pandas as pd
import numpy as np
import s3fs
from boto3 import client
import logging
import os

from datetime import datetime

import utils
from sqlalchemy.sql.expression import column


def get_asset_filepaths():
    """
    get the filepath for most recent csv data dump for each asset
    returns: a dict of {ticker : filepath to most recent csv datadump}
    """
    s3 = client(
        "s3",
        aws_access_key_id=AWS_ACCESS_KEY,
        aws_secret_access_key=AWS_SECRET_KEY,
    )
    datapaths = {}
    page_iterator = s3.get_paginator("list_objects_v2").paginate(Bucket=S3_BUCKET)
    for page in page_iterator:
        for key in page["Contents"]:
            filepath = key["Key"]
            # skip asset metadata
            if filepath.startswith("asset_metadata"):
                continue
            ticker = filepath.split("/")[1].lower()
            # store the filepath to most recent data
            if filepath.endswith("latest.csv"):
                datapaths[ticker] = filepath
    return datapaths


AWS_ACCESS_KEY = os.environ.get("AWS_ACCESS_KEY_ID")
AWS_SECRET_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY")
S3_BUCKET = os.environ.get("S3_BUCKET_FOR_API_DATA", "apidata-dev")
ASSET_FILEPATHS = get_asset_filepaths()


def read_asset_files(data_dir, exclude_coins, exclude_protocols):
    coin_paths = {
        ticker: filepath
        for ticker, filepath in ASSET_FILEPATHS.items()
        if filepath.split("/")[0] == "coin_data"
    }
    # read coin data
    logging.info("reading coin csv files from s3")
    coin_dfs = {
        ticker: pd.read_csv(
            data_dir + coin_path,
            index_col=3,
            storage_options={"key": AWS_ACCESS_KEY, "secret": AWS_SECRET_KEY},
        )
        for ticker, coin_path in coin_paths.items()
        if ticker not in exclude_coins
    }

    lp_paths = {
        ticker: filepath
        for ticker, filepath in ASSET_FILEPATHS.items()
        if filepath.split("/")[0] == "lending_protocol_data"
    }

    # read lending protocol data
    lend_protocol_dfs = {
        ticker: pd.read_csv(
            data_dir + lp_path,
            index_col=0,
            storage_options={"key": AWS_ACCESS_KEY, "secret": AWS_SECRET_KEY},
        )
        for ticker, lp_path in lp_paths.items()
        if ticker not in exclude_protocols
    }

    return coin_dfs, lend_protocol_dfs


def preprocess_coin_data(start_date, coin_dfs, take_rolling_mean=True):
    """
    return a timeseries df with all available coin prices starting
    from the start date. exclude the coins in the exclude_coins
    list
    """
    logging.info("preprocessing coin data")
    start_date = datetime.strptime(start_date, "%Y-%m-%d").date()

    valid_coin_dfs = {}
    for coin_ticker in list(coin_dfs.keys()):
        df = coin_dfs[coin_ticker].copy(deep=True)
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
        df.drop(columns=["timestamp"], inplace=True)

        # if the earliest data is after start_date, skip that coin
        if min(x_values) <= start_date:
            valid_coin_dfs[coin_ticker] = df

    # merge coin prices into one timeseries df
    coin_price_df = utils.merge_dfs(
        valid_coin_dfs, "price", take_rolling_mean=take_rolling_mean
    )
    coin_market_cap_df = utils.merge_dfs(
        valid_coin_dfs, "market_cap", take_rolling_mean=False
    )
    coin_trading_volume_df = utils.merge_dfs(
        valid_coin_dfs, "trading_volume_24h", take_rolling_mean=False
    )

    return coin_price_df, coin_market_cap_df, coin_trading_volume_df


def preprocess_lending_data(
    start_date,
    lend_protocol_dfs,
    coin_price_df,
    training_end_date,
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
    # add anchor protocol
    # interest rate: 19% mean with std 1%
    anchor_index = lend_protocol_dfs["dydx"].index
    lend_protocol_dfs["anc"] = pd.DataFrame(
        {
            "index": anchor_index,
            "lend_rate": np.random.normal(19, 1, len(anchor_index)),
        },
        index=anchor_index,
    )

    logging.info("imputing missing data for lending protocols")
    for protocol, df in lend_protocol_dfs.items():
        df.index = [datetime.strptime(d, "%Y-%m-%d %H:%M:%S").date() for d in df.index]
        # reverse the dataframe so that most recent data is at the tail
        df = df.iloc[::-1]
        # drop na in the beginning and at the end
        df = df.dropna()
        # impute interest rates before the launch date of the protocol
        # using coin prices
        lend_protocol_dfs[protocol] = utils.impute_data(
            X=coin_price_df[["btc", "eth", "usdt", "usdc"]],
            y=df[["lend_rate"]],
            start_date=start_date,
            end_date=training_end_date,
        )
    # merge the dataframes
    lend_rates_df = utils.merge_dfs(
        lend_protocol_dfs, "lend_rate", take_rolling_mean=True
    )

    # start with $1, and apply daily yield each day to convert
    # lend rates to lending protocol (lp) returns
    lp_returns = {protocol: [1.0] for protocol in lend_rates_df.columns}
    for i, _ in enumerate(lend_rates_df.index[:-1]):
        for protocol, returns in lp_returns.items():
            daily_yield = (1 + lend_rates_df.iloc[i][protocol] / 100) ** (1 / 365) - 1
            returns.append(returns[-1] * (1 + daily_yield))
    lp_returns_df = pd.DataFrame(lp_returns, index=lend_rates_df.index)
    return lp_returns_df


def read_asset_metadata(asset_tickers):
    """
    read the asset_metadata
    """
    logging.info("reading asset metadata")
    asset_metadata_df = pd.read_csv(
        f"s3://{S3_BUCKET}/asset_metadata/asset_metadata_2021.10.26.csv",
        index_col=0,
        storage_options={"key": AWS_ACCESS_KEY, "secret": AWS_SECRET_KEY},
    )
    # keep only the metadata about the assets for which we have price data
    asset_metadata_df = asset_metadata_df[
        asset_metadata_df["asset_ticker"].isin(set(asset_tickers))
    ]

    asset_metadata_df["asset_img_url"] = ""
    asset_metadata_df["asset_url"] = ""
    asset_metadata_df["asset_description"] = ""
    asset_metadata_df["risk_assesment"] = [["", ""]] * len(asset_metadata_df)
    return asset_metadata_df


def create_asset_daily_metrics_df(asset_market_cap_df, asset_trading_volume_df):
    asset_market_cap_long_df = utils.convert_wide_to_long(
        asset_market_cap_df, "asset_ticker", "market_cap"
    )

    asset_trading_volume_long_df = utils.convert_wide_to_long(
        asset_trading_volume_df, "asset_ticker", "trading_volume_24h"
    )

    asset_daily_metrics_long_df = pd.merge(
        asset_market_cap_long_df,
        asset_trading_volume_long_df,
        on=["timestamp", "asset_ticker"],
    )
    asset_daily_metrics_long_df["tick_size"] = "1d"
    return asset_daily_metrics_long_df


def read_asset_price_and_metadata(args):
    # first read the data from the csv files
    coin_dfs, lend_protocol_dfs = read_asset_files(
        f"s3://{S3_BUCKET}/", args.exclude_coins, args.exclude_protocols
    )

    # now preprocess the data
    coin_price_df, coin_market_cap_df, coin_trading_volume_df = preprocess_coin_data(
        args.start_date, coin_dfs
    )

    # for lending protocols, the interest rate is converted to returns
    lending_return_df = preprocess_lending_data(
        args.start_date,
        lend_protocol_dfs,
        coin_price_df,
        args.training_end_date,
    )
    # cream finance and compound tickers are different from the protocol names
    lending_return_df.rename(
        columns={"c.r.e.a.m.-finance": "cream", "compound": "comp"}, inplace=True
    )

    asset_price_df = pd.merge(
        coin_price_df, lending_return_df, left_index=True, right_index=True, how="inner"
    )

    asset_daily_metrics_long_df = create_asset_daily_metrics_df(
        coin_market_cap_df, coin_trading_volume_df
    )
    asset_metadata_df = read_asset_metadata(asset_price_df.columns)
    return asset_price_df, asset_metadata_df, asset_daily_metrics_long_df
