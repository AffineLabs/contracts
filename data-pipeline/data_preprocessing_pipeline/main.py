import argparse
import pandas as pd
import os
import logging
import sqlalchemy
import preprocessing
import utils

logging.basicConfig(
    level="INFO",
    format="%(asctime)s [%(levelname)s] %(message)s",
)
pd.set_option("display.max_columns", None)


def get_asset_id_long(asset_metadata_df, asset_price_df):
    """
    asset ids exist in asset metadata dataframe. We need them
    in the long format with timestamp to add to asset price.
    This function converts wide asset_ids to long asset_ids.
    """
    asset_id_wide_df = pd.DataFrame(
        {
            asset_ticker: [i] * len(asset_price_df.index)
            for asset_ticker, i in zip(
                asset_metadata_df["asset_ticker"], asset_metadata_df["asset_id"]
            )
        },
        index=asset_price_df.index,
    )
    # convert asset_id to long format
    asset_id_long_df = utils.convert_wide_to_long(
        asset_id_wide_df, "asset_ticker", "asset_id"
    )
    return asset_id_long_df


def main(args):
    """
    table descriptions: https://docs.google.com/document/d/1nlBXKpbqQwxv4Zypj5nRnNW5GRXQ9gzklQ8v4GuIYUk/edit#
    (page 4)
    """
    (
        asset_price_df,
        asset_metadata_df,
        asset_daily_metrics_df,
    ) = preprocessing.read_asset_price_and_metadata(args)
    # asset_price_df is the data from csv files, which are in wide format
    # convert wide data format to long format
    asset_price_long_df = utils.convert_wide_to_long(
        asset_price_df, "asset_ticker", "closing_price"
    )
    asset_price_long_df["tick_size"] = "1d"
    asset_id_long_df = get_asset_id_long(asset_metadata_df, asset_price_df)

    asset_price_long_df = pd.merge(
        asset_price_long_df,
        asset_id_long_df,
        on=["timestamp", "asset_ticker"],
    )

    asset_daily_metrics_df = pd.merge(
        asset_daily_metrics_df,
        asset_id_long_df,
        on=["timestamp", "asset_ticker"],
    )

    # asset_price_long_df is the asset_price table
    # asset_metadata_df is the asset_metadata table
    # now write the data to the database
    logging.info("writing to aws database.")
    engine = sqlalchemy.create_engine(args.postgres_url)

    # first, clear the existing data in the tables
    with engine.connect() as con:
        con.execute("DELETE FROM asset_metadata;")
        con.execute("DELETE FROM asset_price;")
        con.execute("DELETE FROM asset_daily_metrics;")

    asset_metadata_df.set_index(["asset_id"], inplace=True)
    asset_metadata_df.to_sql("asset_metadata", con=engine, if_exists="append")

    asset_price_long_df.set_index(["asset_id", "tick_size", "timestamp"], inplace=True)
    asset_price_long_df.to_sql("asset_price", con=engine, if_exists="append")

    asset_daily_metrics_df.set_index(
        ["asset_id", "tick_size", "timestamp"], inplace=True
    )
    asset_daily_metrics_df.to_sql("asset_daily_metrics", con=engine, if_exists="append")
    return asset_price_long_df


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--start_date", default="2018-11-26", help="start date for the price data"
    )
    parser.add_argument(
        "--training_end_date",
        default="2021-06-25",
        help="training end date for the model that imputes lending data",
    )
    parser.add_argument(
        "--data_dir",
        default="../../notebook/data/",
        help="data directory for csv data dump",
    )
    parser.add_argument(
        "--postgres_url",
        default=os.environ.get(
            "POSTGRES_REMOTE_URL",
        ),
        help="url for postgres server",
    )
    parser.add_argument(
        "--exclude_coins",
        nargs="+",
        default=["markets", "maker"],
        help="coins to exclude when parsing coin data",
    )
    parser.add_argument(
        "--exclude_protocols",
        nargs="+",
        default=["maker"],
        help="lending protocols to exclude when parsing lending data",
    )

    args = parser.parse_args()
    main(args)
