def list_all_vault_metadata():
    return [
        {
            "vaultName": "Alpine Save",
            "vaultTicker": "alpSave",
            "vaultApy": 8.5,
            "vaultTVL": 10000,
            "assetComp": [
                {
                    "assetTicker": "comp",
                    "assetType": "lending_protocol",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
                {
                    "assetTicker": "aave",
                    "assetType": "lending_protocol",
                    "targetPercentage": 40,
                    "currentPercentage": 40,
                },
                {
                    "assetTicker": "anc",
                    "assetType": "lending_protocol",
                    "targetPercentage": 40,
                    "currentPercentage": 40,
                },
            ],
        },
        {
            "vaultName": "Alpine Balanced",
            "vaultTicker": "alpBal",
            "vaultApy": 42.6,
            "vaultTVL": 10000,
            "assetComp": [
                {
                    "assetTicker": "comp",
                    "assetType": "lending_protocol",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
                {
                    "assetTicker": "aave",
                    "assetType": "lending_protocol",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
                {
                    "assetTicker": "anc",
                    "assetType": "lending_protocol",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
                {
                    "assetTicker": "btc",
                    "assetType": "coin",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
                {
                    "assetTicker": "eth",
                    "assetType": "coin",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
            ],
        },
        {
            "vaultName": "Alpine Aggressive",
            "vaultTicker": "alpAggr",
            "vaultApy": 119.2,
            "vaultTVL": 10000,
            "assetComp": [
                {
                    "assetTicker": "comp",
                    "assetType": "lending_protocol",
                    "targetPercentage": 10,
                    "currentPercentage": 10,
                },
                {
                    "assetTicker": "aave",
                    "assetType": "lending_protocol",
                    "targetPercentage": 10,
                    "currentPercentage": 10,
                },
                {
                    "assetTicker": "anc",
                    "assetType": "lending_protocol",
                    "targetPercentage": 10,
                    "currentPercentage": 10,
                },
                {
                    "assetTicker": "btc",
                    "assetType": "coin",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
                {
                    "assetTicker": "eth",
                    "assetType": "coin",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
                {
                    "assetTicker": "xrp",
                    "assetType": "coin",
                    "targetPercentage": 10,
                    "currentPercentage": 10,
                },
                {
                    "assetTicker": "bch",
                    "assetType": "coin",
                    "targetPercentage": 20,
                    "currentPercentage": 20,
                },
            ],
        },
    ]
