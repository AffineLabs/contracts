import pandas as pd
import numpy as np
import os
from sqlalchemy import create_engine
import logging
import json
import time
from constant import asset_level_portfolios, user_asset_allocations

try:
    import boto3
    from botocore.exceptions import ClientError

    s3 = boto3.resource("s3")
    S3_ENABLED = True
except ImportError:
    logging.warning("Boto3 integration failed, S3 uploading/downloading is disabled.")
    S3_ENABLED = False

logging.basicConfig(
    level="INFO",
    format="%(asctime)s [%(levelname)s] %(message)s",
)
pd.set_option("display.max_columns", None)


def generate_daily_value_and_roi(asset_weights, assets_df, rebalance_period=1):
    """
    given the asset weights, generate the return on $100 initial investment
    rebalances on the last day of each rebalance_period
    """
    investment_total = 100
    asset_allocation = {
        asset_ticker: investment_total * weight
        for asset_ticker, weight in asset_weights.items()
    }
    investment_daily_value = [investment_total]
    for i in range(len(assets_df) - 1):
        for asset_ticker, weight in asset_weights.items():
            asset_price_today = assets_df[asset_ticker][i]
            asset_price_next_day = assets_df[asset_ticker][i + 1]
            asset_allocation[asset_ticker] *= asset_price_next_day / asset_price_today
        investment_total = sum(asset_allocation.values())
        investment_daily_value.append(investment_total)
        # rebalance asset on the last day of the period
        if rebalance_period > 0 and i > 0 and i % rebalance_period == 0:
            asset_allocation = {
                asset: investment_total * weight
                for asset, weight in asset_weights.items()
            }

    roi = np.array([np.round(dv - 100, 3) for dv in investment_daily_value])
    return np.array(investment_daily_value), roi


def apy_from_roi(roi):
    return np.round((roi[-1] + 100) ** (365 / len(roi)) - 100, 3)


def calculate_annualized_volatility(asset_price):
    log_daily_pcnt_change = np.log(asset_price[1:] / asset_price[:-1])
    return np.round(np.std(log_daily_pcnt_change) * 365 ** 0.5, 3)


def get_daily_value_of_asset_portfolios(asset_level_portfolios, asset_price_df):

    lending_protocol_daily_value, _ = generate_daily_value_and_roi(
        asset_level_portfolios["lendingProtocols"],
        asset_price_df,
        rebalance_period=1,
    )
    btceth_daily_value, _ = generate_daily_value_and_roi(
        asset_level_portfolios["btcEth"], asset_price_df, rebalance_period=90
    )
    altcoins_daily_value, _ = generate_daily_value_and_roi(
        asset_level_portfolios["altCoins"], asset_price_df, rebalance_period=90
    )

    investment_daily_value_df = pd.DataFrame(
        {
            "index": asset_price_df.index,
            "lendingProtocols": lending_protocol_daily_value,
            "btcEth": btceth_daily_value,
            "altCoins": altcoins_daily_value,
        }
    )
    investment_daily_value_df.set_index("index", inplace=True)
    return investment_daily_value_df


def upload_to_s3(file_json):
    if S3_ENABLED:
        logging.info("uploading to S3")
        s3 = boto3.client("s3")
        s3.put_object(
            Body=json.dumps(file_json),
            Bucket="portfoliodata-dev",
            Key="portfolio_latest.json",
        )
        # change permission to public read
        resource = boto3.resource("s3")
        object = resource.Bucket("portfoliodata-dev").Object("portfolio_latest.json")
        object.Acl().put(ACL="public-read")

        timestamp = str(time.time())
        s3.put_object(
            Body=json.dumps(file_json),
            Bucket="portfoliodata-dev",
            Key=f"portfolio_{timestamp}.json",
        )
        object = resource.Bucket("portfoliodata-dev").Object(
            f"portfolio_{timestamp}.json"
        )
        object.Acl().put(ACL="public-read")
    else:
        logging.error("failed to upload portfolio returns to S3.")


if __name__ == "__main__":
    logging.info("reading asset price data from aws.")
    engine = create_engine(os.environ.get("POSTGRES_REMOTE_URL"))
    asset_price_long_df = pd.read_sql_table("asset_price", engine)
    # convert data from long to wide format
    asset_price_df = asset_price_long_df.pivot(
        index="timestamp", columns="asset_ticker", values="closing_price"
    )
    asset_price_df.index = [str(date) for date in asset_price_df.index]

    logging.info(
        "generating daily historical value and roi for each asset class level portfolio."
    )
    investment_daily_value_df = get_daily_value_of_asset_portfolios(
        asset_level_portfolios, asset_price_df
    )

    logging.info("populating the json object with portfolio returns.")
    output_json = {}
    for i in range(1, 6):
        user_investment_daily_value, user_roi = generate_daily_value_and_roi(
            user_asset_allocations[f"risk{i}"],
            investment_daily_value_df,
            rebalance_period=90,
        )
        annual_vol = calculate_annualized_volatility(user_investment_daily_value) * 100

        output_json[f"risk{i}"] = {
            "lendingProtocols": {
                "tickers": list(asset_level_portfolios["lendingProtocols"].keys()),
                "percentage": user_asset_allocations[f"risk{i}"]["lendingProtocols"]
                * 100,
            },
            # "automatedMarketMaking": {
            #     "tickers": [],
            #     "percentage": 0.0,
            # },
            "btcEth": {
                "tickers": ["btc", "eth"],
                "percentage": user_asset_allocations[f"risk{i}"]["btcEth"] * 100,
            },
            "altCoins": {
                "tickers": list(asset_level_portfolios["altCoins"].keys()),
                "percentage": user_asset_allocations[f"risk{i}"]["altCoins"] * 100,
            },
            "historicalRoi": dict(zip(asset_price_df.index, user_roi)),
            "projectedApy": apy_from_roi(user_roi),
            "projectedApyRange": [
                apy_from_roi(user_roi) - annual_vol,
                apy_from_roi(user_roi) + annual_vol,
            ],
        }

        # delete portfolios with weight 0
        for portfolio_name in ["btcEth", "altCoins"]:
            if output_json[f"risk{i}"][portfolio_name]["percentage"] == 0:
                del output_json[f"risk{i}"][portfolio_name]

    output_json["risk1"]["fullname"] = "Multiplyr Cash"
    output_json["risk2"]["fullname"] = "Multiplyr Cash Aggresive"
    output_json["risk3"]["fullname"] = "Multiplyr Balanced"
    output_json["risk4"]["fullname"] = "Multiplyr Coin"
    output_json["risk5"]["fullname"] = "Multiplyr Coin Aggresive"

    with open("out.json", "w") as out:
        json.dump(output_json, out)

    upload_to_s3(output_json)
