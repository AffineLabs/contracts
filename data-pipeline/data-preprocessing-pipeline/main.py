import argparse
import pandas as pd
from datetime import datetime, timedelta
from preprocessing import (
    preprocess_coin_data,
    preprocess_lending_data,
    read_asset_prices,
)
from utils import convert_wide_to_long


def main(args):
    asset_price_df = read_asset_prices(args)
    asset_price_long_df = convert_wide_to_long(
        asset_price_df, "asset_ticker", "closing_price"
    )
    asset_price_long_df["tick_size"] = "1d"

    asset_id_wide_df = pd.DataFrame(
        {
            asset_ticker: [i] * len(asset_price_df.index)
            for i, asset_ticker in enumerate(asset_price_df.columns)
        },
        index=asset_price_df.index,
    )
    asset_id_long_df = convert_wide_to_long(
        asset_id_wide_df, "asset_ticker", "asset_id"
    )

    asset_price_long_df = pd.merge(
        asset_price_long_df,
        asset_id_long_df,
        how="inner",
        left_on=["timestamp", "asset_ticker"],
        right_on=["timestamp", "asset_ticker"],
    )
    # this is the asset_price table
    # TODO: convert this df into an sql table
    return asset_price_long_df


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--start_date", default="2018-11-26", help="start date for the price data"
    )
    parser.add_argument(
        "--training_end_date",
        default="2021-02-25",
        help="training end date for the model that imputes lending data",
    )
    parser.add_argument(
        "--data_dir",
        default="../../../notebook/data/",
        help="data directory for csv data dump",
    )
    parser.add_argument(
        "--exclude_coins",
        nargs="+",
        default=["markets.csv", "maker.csv"],
        help="coins to exclude when parsing coin data",
    )
    parser.add_argument(
        "--exclude_protocols",
        nargs="+",
        default=["maker.csv", "aave.csv"],
        help="lending protocols to exclude when parsing lending data",
    )

    parser.add_argument(
        "--pred_coins",
        nargs="+",
        default=["bitcoin", "ethereum", "tether", "usd-coin"],
        help="coin prices to use to predict missing lending data",
    )

    args = parser.parse_args()
    main(args)
