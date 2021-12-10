from fastapi import FastAPI
import uvicorn
from . import user_info, asset_info, vault_info, constant, utils

app = FastAPI(
    title="Alpine Web API",
    version=constant.API_VERSION,
    description=constant.API_DESC,
)


@app.get(
    "/",
    summary=f"Welcome to Alpine Web API v{constant.API_VERSION}",
    responses={
        200: utils.create_json_response(
            {
                "message": f"Alpine Web API v{constant.API_VERSION}. "
                "Visit /docs for documentation"
            }
        )
    },
)
async def root():
    return {"message": "Alpine Web API v0.1.0. Visit /docs for documentation"}


# using camel case for param names for consistency with return objects
# vault_info.py


@app.get(
    "/listAllVaultMetadata",
    summary="get metadata for all vaults",
    description="get vault name, ticker, TVL, apy, and asset composition for all alpine vaults.",
    response_description=("returns a list of metadata for all alpine vaults."),
    responses={
        200: utils.create_json_response(
            [
                {
                    "vaultName": "Alpine Save",
                    "vaultTicker": "alpSave",
                    "vaultApy": 10.0,
                    "vaultTVL": 10000,
                    "assetComp": [
                        {
                            "assetTicker": "comp",
                            "assetType": "lending_protocol",
                            "targetPercentage": 30,
                            "currentPercentage": 20,
                        },
                        {
                            "assetTicker": "btc",
                            "assetType": "coin",
                            "targetPercentage": 70,
                            "currentPercentage": 80,
                        },
                    ],
                }
            ]
        )
    },
)
async def handle_list_all_vault_metadata():
    return vault_info.list_all_vault_metadata()


# user_info.py
@app.post(
    "/updateUserProfile",
    summary="update a user profile. "
    " If the method is called with a new email address, a new user "
    "profile is created in the backend. ",
    description="create and update user profiles.",
    response_description="returns current user profile from the backend.",
    responses={
        200: utils.create_json_response(
            {
                "email": "user@tryalpine.com",
                "userId": 1,
                "isOnboarded": True,
                "publicAddress": "0xfakeaddr",
            }
        )
    },
)
async def handle_update_user_profile(
    profile: constant.UserProfile,
):
    return user_info.update_user_profile(profile)


@app.get(
    "/getUserHistoricalBalance",
    summary="get historical balance of the user",
    description="get historical balance of the user.",
    response_description="If user id is 1, returns a fake user balance history assuming the user "
    "invested 10k in Alpine Balanced strategy on 2018-11-26. Otherwise returns an error messge",
    responses={
        200: utils.create_json_response(
            {
                "userId": 1,
                "historicalBalance": {
                    "2021-10-09 00:00:00": 1203.33,
                    "2021-10-10 00:00:00": 1207.33,
                },
            }
        )
    },
)
async def handle_get_user_historical_balance(userId: int = constant.USER_ID_QUERY):
    return user_info.get_historical_balance(userId)


@app.get(
    "/listAllAssetTickers",
    summary="get all supported asset tickers",
    description="get all supported asset tickers.",
    response_description="",
    responses={
        200: utils.create_json_response(
            [
                "btc",
                "aave",
                "comp",
            ]
        )
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
    "(0-5; lower is better), market cap, 24 hours trading volume, 52 "
    "week high and low.",
    response_description="*Note: `defiSafetyScore`, `marketCap` and "
    "`tradingVol24h` can be null.*",
    responses={
        200: utils.create_json_response(
            {
                "assetTicker": "comp",
                "assetId": 22,
                "assetFullname": "Compound",
                "assetType": "lending_protocol",
                "defiSafetyScore": 8,
                "alpineRiskScore": 1,
                "marketCap": 1321311343.23,
                "tradingVol24h": 1212223.23,
                "apy": 4.2,
                "52WeekHigh": 1.1412971156811462,
                "52WeekLow": 1.0978781938067743,
            }
        )
    },
)
async def handle_get_asset_metadata(assetTicker: str = constant.ASSET_TICKER_QUERY):
    return asset_info.get_asset_metadata(assetTicker)


@app.get(
    "/getAssetHistoricalPrice",
    summary="get asset historical price",
    description="get asset historical price",
    response_description="returns asset historical price",
    responses={
        200: utils.create_json_response(
            {
                "assetTicker": "btc",
                "historicalPrice": {
                    "2021-10-09 00:00:00": 60003.33,
                    "2021-10-10 00:00:00": 60010.43,
                },
            }
        )
    },
)
async def handle_get_asset_historical_price(
    assetTicker: str = constant.ASSET_TICKER_QUERY,
):
    return asset_info.get_historical_price(assetTicker)


def run():
    uvicorn.run("apis.alpine_web_api.main:app", host="0.0.0.0", port=8000, reload=True)


if __name__ == "__main__":
    run()
