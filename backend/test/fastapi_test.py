import pathlib

from pandas import read_csv
from unittest.mock import patch

from fastapi.testclient import TestClient
from apis.alpine_web_api.main import app
from apis.alpine_web_api import utils

from _pytest.monkeypatch import MonkeyPatch

client = TestClient(app)

# Define the constant mock objects
TEST_CSV_PATHS = (pathlib.Path(__file__).parent / "mock_files")
PATCH_ASSET_METADATA_DF = lambda: read_csv(TEST_CSV_PATHS / "all_asset_metadata.csv", index_col=0)
PATCH_ASSET_PRICE_DF = lambda x: read_csv(TEST_CSV_PATHS / "asset_price.csv", index_col=0, parse_dates=["timestamp"])
PATCH_DAILY_METRICS_DF = lambda x: read_csv(TEST_CSV_PATHS / "daily_metrics.csv", index_col=0, parse_dates=["timestamp"])
PATCH_USER_BALANCE_DF = lambda x: read_csv(TEST_CSV_PATHS / "user_balance.csv", index_col=0, parse_dates=["timestamp"])

monkeypatch = MonkeyPatch()
monkeypatch_attrs = {
    "get_all_asset_metadata": PATCH_ASSET_METADATA_DF,
    "get_asset_price_from_sql": PATCH_ASSET_PRICE_DF,
    "get_asset_daily_metrics_from_sql": PATCH_DAILY_METRICS_DF,
    "get_user_balance_from_sql": PATCH_USER_BALANCE_DF
}
for key, value in monkeypatch_attrs.items():
    monkeypatch.setattr(utils, key, value)

MOCK_ASSET_METADATA = {
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

MOCK_HISTORICAL_PRICE = {
    "assetTicker": "btc",
    "historicalPrice": {
        "2021-10-09 00:00:00": 60003.33,
        "2021-10-10 00:00:00": 60010.43,
    }
}

MOCK_USER_HISTORICAL_BALANCE = {
    "historicalBalance": {
        "2021-10-09 00:00:00": 1203.33,
        "2021-10-10 00:00:00": 1207.33,
    },
}

MOCK_ADDRESS = "0x69b3ce79B05E57Fc31156fEa323Bd96E6304852D"
MOCK_NONEXISTENT_ASSET = "AJLKHSSDNMS"
MOCK_EXISTENT_ASSET = "btc"

# Define the expected response code
SUCCESS_RESPONSE_CODE = 200
NOT_FOUND_REPSONSE_CODE = 200  # TODO (adib): update the API and change this

def test_read_main():
    response = client.get("/")
    assert response.status_code == SUCCESS_RESPONSE_CODE
    assert "message" in response.json()
    assert "Alpine Web API v" in response.json()["message"]
    assert "Visit /docs for documentation" in response.json()["message"] 

def test_all_vault_metadata():
    response = client.get("/listAllVaultMetadata")
    assert response.status_code == SUCCESS_RESPONSE_CODE
    vault_list = response.json()
    for vault_info in vault_list:
        for key in ['vaultName', 'vaultAddress', 'vaultAbi',
                    'vaultTicker', 'assetComp', 'vaultApy']:
            assert key in vault_info
        # This test is failing right now, but it should not.
        # Every vault should have an APY, even stable ones.
        assert vault_info['vaultApy'] >= 0.
        total_asset_alloc = sum([asset['targetPercentage'] for asset in vault_info['assetComp']])
        # Even stable vaults should have an allocation adding up to 100
        assert total_asset_alloc == 100.

def test_user_historical_balance():
    response = client.get("/getUserHistoricalBalance", params={"userId": 1})
    assert response.status_code == SUCCESS_RESPONSE_CODE
    assert "historicalBalance" in response.json()
    balances = response.json()["historicalBalance"]
    assert all(x >= 0. for x in balances.values())

def test_user_public_address():
    response = client.get("/getUserPublicAddress", params={"userId": 1})
    assert response.status_code == SUCCESS_RESPONSE_CODE
    assert len(response.json()["publicAddress"]) == len(MOCK_ADDRESS)

def test_list_all_asset_tickers():
    response = client.get("/listAllAssetTickers")
    assert response.status_code == SUCCESS_RESPONSE_CODE
    assert isinstance(response.json(), list)
    assert len(response.json()) > 0

def test_list_asset_metadata():
    response = client.get("/getAssetMetadata", params={"assetTicker": MOCK_EXISTENT_ASSET})
    assert response.status_code == SUCCESS_RESPONSE_CODE
    asset_metadata_dict = response.json()
    for key in MOCK_ASSET_METADATA.keys():
        assert key in asset_metadata_dict
    assert asset_metadata_dict["52WeekHigh"] > asset_metadata_dict["52WeekLow"]

def test_asset_historical_price():
    response = client.get("/getAssetHistoricalPrice", params={"assetTicker": MOCK_EXISTENT_ASSET})
    assert response.status_code == SUCCESS_RESPONSE_CODE
    prices = response.json()["historicalPrice"]
    assert all(x > 0 for x in prices.values())

def test_list_nonexisting_asset():
    response = client.get("/getAssetMetadata", 
                          params={"assetTicker": MOCK_NONEXISTENT_ASSET})
    assert response.status_code == NOT_FOUND_REPSONSE_CODE

def test_user_nonexistent_historical_balance():
    response = client.get("/getUserHistoricalBalance", 
                          params={"userId": -1})
    assert response.status_code == NOT_FOUND_REPSONSE_CODE
    
def test_user_nonexistent_public_address():
    response = client.get("/getUserPublicAddress", 
                          params={"userId": -1})
    assert response.status_code == NOT_FOUND_REPSONSE_CODE


def test_nonexistent_asset_historical_price():
    response = client.get("/getAssetHistoricalPrice", 
                          params={"assetTicker": MOCK_NONEXISTENT_ASSET})
    assert response.status_code == NOT_FOUND_REPSONSE_CODE






