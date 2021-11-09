from unittest.mock import patch

from fastapi.testclient import TestClient
from apis.alpine_web_api.main import app


client = TestClient(app)

def test_read_main():
    response = client.get("/")
    assert response.status_code == 200
    assert "message" in response.json()
    assert "Alpine Web API v" in response.json()["message"]
    assert "Visit /docs for documentation" in response.json()["message"] 

def test_all_vault_metadata():
    response = client.get("/listAllVaultMetadata")
    assert response.status_code == 200
    vault_list = response.json()
    for vault_info in vault_list:
        print(vault_info['vaultName'])
        for key in ['vaultName', 'vaultAddress', 'vaultAbi',
                    'vaultTicker', 'assetComp']:
            assert key in vault_info
        # This test is failing right now, but it should not.
        # Every vault should have an APY, even stable ones.
        assert vault_info['vaultApy'] >= 0.
        total_asset_alloc = sum([asset['targetPercentage'] for asset in vault_info['assetComp']])
        # Even stable vaults should have an allocation adding up to 100
        assert total_asset_alloc == 100


def test_user_historical_balance():
    response = client.get("/getUserHistoricalBalance", params={"userId": 1})
    assert response.status_code == 200


def test_user_nonexistent_historical_balance():
    response = client.get("/getUserHistoricalBalance", params={"userId": -1})
    assert response.status_code == 404


def test_user_public_address():
    response = client.get("/getUserPublicAddress", params={"userId": 1})
    assert response.status_code == 200


def test_user_nonexistent_public_address():
    response = client.get("/getUserPublicAddress", params={"userId": -1})
    assert response.status_code == 404


def test_list_all_asset_tickers():
    response = client.get("/listAllAssetTickers")
    assert response.status_code == 200


def test_list_asset_metadata():
    response = client.get("/getAssetMetadata", params={"assetTicker": "comp"})
    assert response.status_code == 200


def test_list_nonexisting_asset():
    response = client.get("/getAssetMetadata", params={"assetTicker": "AJLKHSSDNMS"})
    assert response.status_code == 404


def test_asset_historical_price():
    response = client.get("/getAssetHistoricalPrice", params={"assetTicker": "comp"})
    assert response.status_code == 200


def test_nonexistent_asset_historical_price():
    response = client.get("/getAssetHistoricalPrice", params={"assetTicker": "AJLKHSSDNMS"})
    assert response.status_code == 404






