import pandas as pd
import numpy as np
import os
from sqlalchemy import create_engine
import logging
import json
import time

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
    rebalances on the first day of each rebalance_period
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
        if rebalance_period > 0 and i % rebalance_period == 0:
            asset_allocation = {
                asset: investment_total * weight
                for asset, weight in asset_weights.items()
            }

    roi = np.array([np.round(dv - 100, 3) for dv in investment_daily_value])
    return np.array(investment_daily_value), roi


def apy_from_roi(roi):
    return np.round(roi[-1] / len(roi) * 365, 3)


def calculate_annualized_volatility(asset_price):
    log_daily_pcnt_change = np.log(asset_price[1:] / asset_price[:-1]) * 100
    return np.round(np.std(log_daily_pcnt_change) * 365 ** 0.5, 3)


engine = create_engine(os.environ.get("POSTGRES_REMOTE_URL"))
logging.info("reading asset price data from aws.")
asset_price_long_df = pd.read_sql_table("asset_price", engine)
# convert data from long to wide format
asset_price_df = asset_price_long_df.pivot(
    index="timestamp", columns="asset_ticker", values="closing_price"
)
asset_price_df.index = [str(date) for date in asset_price_df.index]

asset_level_portfolios = {
    "lendingProtocols": {
        "aave": 0.3,
        "compound": 0.1,
        "dydx": 0.2,
        "definer": 0.1,
        "c.r.e.a.m.-finance": 0.3,
    },
    "btcEth": {"btc": 0.5, "eth": 0.5},
    "altCoins": {
        "xrp": 0.2,
        "bch": 0.05,
        "eos": 0.05,
        "xlm": 0.05,
        "ltc": 0.1,
        "bsv": 0.05,
        "trx": 0.2,
        "ada": 0.05,
        "miota": 0.05,
        "xmr": 0.2,
    },
    "automatedMarketMaking": {},
}

user_asset_allocations = {
    "risk1": {
        "lendingProtocols": 1.0,
        "btcEth": 0.0,
        "altCoins": 0.0,
    },
    "risk2": {
        "lendingProtocols": 0.8,
        "btcEth": 0.2,
        "altCoins": 0.0,
    },
    "risk3": {
        "lendingProtocols": 0.6,
        "btcEth": 0.4,
        "altCoins": 0.0,
    },
    "risk4": {
        "lendingProtocols": 0.4,
        "btcEth": 0.4,
        "altCoins": 0.2,
    },
    "risk5": {
        "lendingProtocols": 0.2,
        "btcEth": 0.4,
        "altCoins": 0.4,
    },
}

logging.info(
    "generating daily historical value and roi for each asset class level portfolio."
)
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

logging.info("populating the json object with portfolio returns.")
output_json = {}
for i in range(1, 6):
    user_investment_daily_value, user_roi = generate_daily_value_and_roi(
        user_asset_allocations[f"risk{i}"],
        investment_daily_value_df,
        rebalance_period=90,
    )
    annual_vol = calculate_annualized_volatility(user_investment_daily_value)

    output_json[f"risk{i}"] = {
        "lendingProtocols": {
            "tickers": list(asset_level_portfolios["lendingProtocols"].keys()),
            "percentage": user_asset_allocations[f"risk{i}"]["lendingProtocols"] * 100,
        },
        "automatedMarketMaking": {
            "tickers": [],
            "percentage": 0.0,
        },
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

output_json["risk1"]["fullname"] = "Multiplyr Cash"
output_json["risk2"]["fullname"] = "Multiplyr Cash Aggresive"
output_json["risk3"]["fullname"] = "Multiplyr Balanced"
output_json["risk4"]["fullname"] = "Multiplyr Coin"
output_json["risk5"]["fullname"] = "Multiplyr Coin Aggresive"

if S3_ENABLED:
    logging.info("uploading to S3")
    s3 = boto3.client("s3")
    s3.put_object(
        Body=json.dumps(output_json),
        Bucket="portfoliodata-dev",
        Key="portfolio_latest.json",
    )

    s3.put_object(
        Body=json.dumps(output_json),
        Bucket="portfoliodata-dev",
        Key=f"portfolio_{str(time.time())}.json",
    )
else:
    logging.error("failed to upload portfolio returns to S3.")
