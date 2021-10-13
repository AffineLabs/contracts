import pandas as pd
import numpy as np
import os
from sqlalchemy import create_engine
import logging
import json
import time
import constant


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


def generate_daily_value_and_roi(asset_weights, asset_prices_df, rebalance_period=1):
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
    for i in range(len(asset_prices_df) - 1):
        for asset_ticker, weight in asset_weights.items():
            asset_price_today = asset_prices_df[asset_ticker][i]
            asset_price_next_day = asset_prices_df[asset_ticker][i + 1]
            asset_allocation[asset_ticker] *= asset_price_next_day / asset_price_today
        investment_total = sum(asset_allocation.values())
        investment_daily_value.append(investment_total)
        # rebalance asset on the last day of the period
        if rebalance_period > 0 and i > 0 and i % rebalance_period == 0:
            asset_allocation = {
                asset: investment_total * weight
                for asset, weight in asset_weights.items()
            }
    roi = np.array([dv - 100 for dv in investment_daily_value])
    return np.array(investment_daily_value), roi


def apy_from_roi(roi, num_days):
    """
    given the return on investment (roi) and length of a period in days,
    computes the apy at the end of the period
    params:
        roi: return on investpent (roi) as percentage
        num_days: the duration in days
    returns: apy as percentage
    """
    num_years = num_days / 365
    investment_total_growth = roi / 100 + 1
    annual_yield = investment_total_growth ** (1 / num_years) - 1
    # return apy as percentage
    return annual_yield * 100


def calculate_annualized_volatility(asset_price):
    """
    calculate annualized volatility from asset price
    """
    log_daily_pcnt_change = np.log(asset_price[1:] / asset_price[:-1])
    return np.round(np.std(log_daily_pcnt_change) * 365 ** 0.5, 3)


def calculate_asset_apy(daily_prices):
    """
    calculate apy from an asset's daily prices during a period
    param: daily_prices - a list or pd Series
    """
    asset_roi = (daily_prices[-1] / daily_prices[0] - 1) * 100
    asset_apy = apy_from_roi(asset_roi, len(daily_prices))
    return asset_apy


def asset_last_24h_change(daily_prices):
    """
    calculate change in asset price as pct in the last 24 hours
    """
    # not enough price data points to compute daily change, so return 0
    if len(daily_prices) < 2:
        return 0.0
    todays_price = daily_prices[-1]
    previous_price = daily_prices[-2]
    return (todays_price - previous_price) / previous_price * 100


def get_daily_value_of_asset_portfolios(asset_weights, asset_prices_df):
    """
    for each asset class (eg. lending protocol, btc-eth etc),
    given portfolio weights of assets in that class
    this function calculates the daily value of the portfolio.
    """
    lending_protocol_daily_value, _ = generate_daily_value_and_roi(
        asset_weights["lendingProtocols"],
        asset_prices_df,
        rebalance_period=1,
    )
    btceth_daily_value, _ = generate_daily_value_and_roi(
        asset_weights["btcEth"], asset_prices_df, rebalance_period=90
    )
    altcoins_daily_value, _ = generate_daily_value_and_roi(
        asset_weights["altCoins"], asset_prices_df, rebalance_period=90
    )

    investment_daily_value_df = pd.DataFrame(
        {
            "index": asset_prices_df.index,
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


def get_asset_info(
    ticker,
    asset_id,
    asset_prices_df,
    asset_type_weights,
    asset_weights,
    asset_type,
):
    asset_level_portfolio_weight = asset_type_weights[asset_type]
    asset_weight = asset_weights[asset_type][ticker]

    return {
        "ticker": ticker,
        "assetId": asset_id,
        "apy": calculate_asset_apy(asset_prices_df[ticker]),
        "lastPrice": asset_prices_df[ticker][-1],
        "last24hPercentChange": asset_last_24h_change(asset_prices_df[ticker]),
        "portfolioPercentage": asset_weight * asset_level_portfolio_weight * 100,
    }


if __name__ == "__main__":
    logging.info("reading asset price data from aws.")
    engine = create_engine(os.environ.get("POSTGRES_REMOTE_URL"))
    asset_price_long_df = pd.read_sql_table("asset_price", engine)
    # convert data from long to wide format
    asset_prices_df = asset_price_long_df.pivot(
        index="timestamp", columns="asset_ticker", values="closing_price"
    )

    asset_ticker_to_asset_id = dict(
        zip(asset_price_long_df["asset_ticker"], asset_price_long_df["asset_id"])
    )
    logging.info(
        "generating daily historical value and roi for each asset class level portfolio."
    )
    investment_daily_value_df = get_daily_value_of_asset_portfolios(
        constant.asset_level_portfolios, asset_prices_df
    )

    logging.info("populating the json object with portfolio returns.")
    output_json = {}
    for i in range(1, 6):
        # user_asset_weights is the weight of different asset level portfolios in user portfolio
        # this changes as the underlying asset_prices_change
        (user_investment_daily_value, user_roi,) = generate_daily_value_and_roi(
            constant.user_asset_allocations[f"risk{i}"],
            investment_daily_value_df,
            rebalance_period=90,
        )
        annual_vol = calculate_annualized_volatility(user_investment_daily_value) * 100
        # get apy pcnt from roi
        apy = apy_from_roi(user_roi[-1], len(user_roi))

        output_json[f"risk{i}"] = {
            "lendingProtocols": {
                "tickers": [
                    get_asset_info(
                        ticker,
                        asset_ticker_to_asset_id[ticker],
                        asset_prices_df,
                        constant.user_asset_allocations[f"risk{i}"],
                        constant.asset_level_portfolios,
                        "lendingProtocols",
                    )
                    for ticker in constant.asset_level_portfolios[
                        "lendingProtocols"
                    ].keys()
                ],
                "percentage": constant.user_asset_allocations[f"risk{i}"][
                    "lendingProtocols"
                ]
                * 100,
            },
            # "automatedMarketMaking": {
            #     "tickers": [],
            #     "percentage": 0.0,
            # },
            "btcEth": {
                "tickers": [
                    get_asset_info(
                        ticker,
                        asset_ticker_to_asset_id[ticker],
                        asset_prices_df,
                        constant.user_asset_allocations[f"risk{i}"],
                        constant.asset_level_portfolios,
                        "btcEth",
                    )
                    for ticker in constant.asset_level_portfolios["btcEth"].keys()
                ],
                "percentage": constant.user_asset_allocations[f"risk{i}"]["btcEth"]
                * 100,
            },
            "altCoins": {
                "tickers": [
                    get_asset_info(
                        ticker,
                        asset_ticker_to_asset_id[ticker],
                        asset_prices_df,
                        constant.user_asset_allocations[f"risk{i}"],
                        constant.asset_level_portfolios,
                        "altCoins",
                    )
                    for ticker in constant.asset_level_portfolios["altCoins"].keys()
                ],
                "percentage": constant.user_asset_allocations[f"risk{i}"]["altCoins"]
                * 100,
            },
            "historicalRoi": dict(
                zip(asset_prices_df.index.strftime("%Y-%m-%d %H:%M:%S"), user_roi)
            ),
            "projectedApy": apy,
            "projectedApyRange": [
                apy - annual_vol,
                apy + annual_vol,
            ],
        }

        # delete portfolios with weight 0
        for portfolio_name in ["btcEth", "altCoins"]:
            if output_json[f"risk{i}"][portfolio_name]["percentage"] == 0:
                del output_json[f"risk{i}"][portfolio_name]

    output_json["risk1"]["fullname"] = "Multiplyr Cash"
    output_json["risk2"]["fullname"] = "Multiplyr Balanced"
    output_json["risk3"]["fullname"] = "Multiplyr Btc-Eth"
    output_json["risk4"]["fullname"] = "Multiplyr Alt Coin"
    output_json["risk5"]["fullname"] = "Multiplyr Alt Coin Aggresive"

    # with open("out.json", "w") as out:
    #     json.dump(output_json, out)
    upload_to_s3(output_json)
