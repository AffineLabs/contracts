from typing import List

from fastapi import FastAPI, Query
import uvicorn
from . import user_info, asset_info, vault_info

VERSION = "0.1.1"

app = FastAPI(
    title="Alpine Web API",
    version=VERSION,
    description="Welcome to the Alpine Web API!",
)
USER_ID_DESC = ("user id. For MV0, only one user with id 1 is supported.",)
ASSET_TICKER_DESC = "case insensitive asset ticker."


@app.get(
    "/",
    summary=f"Welcome to Alpine Web API v{VERSION}",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": {
                        "message": "Alpine Web API v0.1.0. Visit /docs for documentation"
                    }
                }
            },
        }
    },
)
async def root():
    return {"message": "Alpine Web API v0.1.0. Visit /docs for documentation"}


# using camel case for param names for consistency with return objects
@app.get(
    "/listAllVaultMetadata",
    summary="get metadata for all vaults",
    description="get vault name, ticker, address, asset composition, abi for all alpine vaults.",
    response_description="For MV0, returns metadata for only one vault",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": [
                        {
                            "vaultName": "Alpine Save",
                            "vaultAddress": "0x6076f3011c987A19a04e2B6a37A96Aed1ee01492",
                            "vaultTicker": "alpSave",
                            "assetComp": [
                                {"assetTicker": "comp", "targetPercentage": 30},
                                {"assetTicker": "aave", "targetPercentage": 40},
                                {"assetTicker": "dydx", "targetPercentage": 30},
                            ],
                            "vaultAbi": {},
                        }
                    ]
                }
            }
        },
    },
)
async def handle_list_all_vault_metadata():
    return vault_info.list_all_vault_metadata()


# user_info.py


@app.get(
    "/getUserHistoricalBalance",
    summary="get historical balance of the user",
    description="get historical balance of the user.",
    response_description="If user id is 1, returns a fake user balance history assuming the user "
    "invested 10k in Alpine Balanced strategy on 2018-11-26. Otherwise returns an error messge",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": {
                        "userId": 1,
                        "historicalBalance": {
                            "2021-10-09 00:00:00": 1203.33,
                            "2021-10-10 00:00:00": 1207.33,
                        },
                    }
                }
            },
        }
    },
)
async def handle_get_user_historical_balance(
    userId: int = Query(..., description=USER_ID_DESC, title="user id")
):
    """
    get historical balance of the user. For now, if the
    user id is 1, returns a fake user balance history, otherwise
    returns an error messge
    Params:
        (int) userId: user id
    Returns: {
        (int)  userId           : user id,
        (dict) historicalBalance: { timestamp : user balance at timestamp }
    }
    """
    return user_info.get_historical_balance(userId)


@app.get(
    "/getUserPublicAddress",
    summary="get public address of the user",
    description="get public address of the user.",
    response_description="If user id is 1, returns a fake public address, "
    "otherwise returns an error messge",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": {
                        "userId": 1,
                        "publicAddress": "0xfakeaddr",
                    }
                }
            },
        }
    },
)
async def handle_get_user_public_address(
    userId: int = Query(..., description=USER_ID_DESC, title="user id")
):
    return user_info.get_user_public_address(userId)


@app.get(
    "/listAllAssetTickers",
    summary="get all supported asset tickers",
    description="get all supported asset tickers.",
    response_description="",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": [
                        "bnb",
                        "doge",
                        "btc",
                        "ltc",
                        "ada",
                        "miota",
                        "eth",
                        "trx",
                        "usdt",
                        "vet",
                        "theta",
                        "bch",
                        "etc",
                        "xlm",
                        "neo",
                        "eos",
                        "xrp",
                        "xmr",
                        "link",
                        "aave",
                        "comp",
                        "cream",
                        "dydx",
                        "definer",
                    ]
                }
            }
        },
    },
)
async def handle_list_all_asset_tickers():
    """
    list all supported asset tickers
    """
    return [
        "bnb",
        "doge",
        "btc",
        "ltc",
        "ada",
        "miota",
        "eth",
        "trx",
        "usdt",
        "vet",
        "theta",
        "bch",
        "etc",
        "xlm",
        "neo",
        "eos",
        "xrp",
        "xmr",
        "link",
        "aave",
        "comp",
        "cream",
        "dydx",
        "definer",
    ]


# asset_info.py
@app.get(
    "/getAssetMetadata",
    summary="get asset metadata",
    description="get internal asset id, asset fullname, asset type, "
    "DeFi safety score (0-10; higher is better), Alpine risk score "
    "(0-5; lower is better), market cap, 24 hours trading volume, 52 week high and low.",
    response_description="*Note: `defiSafetyScore`, `marketCap` and `tradingVol24h` can be null.*",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": {
                        "assetTicker": "comp",
                        "assetId": 22,
                        "assetFullname": "Compound",
                        "assetType": "lending_protocol",
                        "defiSafetyScore": 8,
                        "alpineRiskScore": 1,
                        "marketCap": 1321311343.23,
                        "tradingVol24h": 1212223.23,
                        "52WeekHigh": 1.1412971156811462,
                        "52WeekLow": 1.0978781938067743,
                    }
                }
            },
        }
    },
)
async def handle_get_asset_metadata(
    assetTicker: str = Query(..., description=ASSET_TICKER_DESC, title="asset ticker")
):
    """
    get metadata for an asset.
    Params:
        (str) assetTicker: asset ticker. For lending protocols, the ticker is the same as their
                           full name eg. aave, compound, c.r.e.a.m-finance, dydx and definer
    Returns:
        {
            (str)   assetTicker    : asset ticker,
            (int)   assetId        : an internal, unique asset id,
            (str)   assetFullname  : full name of the asset,
            (float) marketCap      : total market cap of the asset;
                                     nullable,
            (float) tradingVol24h  : trading volume of the asset in the last 24 hours;
                                     nullable,
            (float) 52WeekHigh     : highest asset price in last 52 weeks,
            (float) 52WeekLow      : lowest asset price in last 52 weeks,
        }
    """

    return asset_info.get_asset_metadata(assetTicker)


@app.get(
    "/getAssetHistoricalPrice",
    summary="get asset historical price",
    description="get asset historical price",
    response_description="returns asset historical price",
    responses={
        200: {
            "content": {
                "application/json": {
                    "example": {
                        "assetTicker": "btc",
                        "historicalPrice": {
                            "2021-10-09 00:00:00": 60003.33,
                            "2021-10-10 00:00:00": 60010.43,
                        },
                    }
                }
            },
        }
    },
)
async def handle_get_asset_historical_price(
    assetTicker: str = Query(..., description=ASSET_TICKER_DESC, title="asset ticker")
):
    """
    get historical price of an asset.
    Params:
        (str) assetTicker: asset ticker. For lending protocols, the ticker is the same as their
                           full name eg. aave, compound, c.r.e.a.m-finance, dydx and definer
    Returns:
        {
            (str)  assetTicker    : asset ticker,
            (dict) historicalPrice: { timestamp : asset price at timestamp }
        }
    """
    return asset_info.get_historical_price(assetTicker)


# # routes/transactions.py
# @app.get("/transactions/{user_id}/")
# async def get_transactions(user_id: int, asset_tickers: List[str] = Query(["all"])):
#     return transactions.user_transactions(user_id, asset_tickers)


def run():
    uvicorn.run("apis.alpine_web_api.main:app", host="0.0.0.0", port=8000, reload=False)


if __name__ == "__main__":
    run()
