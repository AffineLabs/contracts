def list_all_vault_metadata():
    return [
        {
            "vaultName": "Alpine Save",
            "vaultAddress": "0x6076f3011c987A19a04e2B6a37A96Aed1ee01492",
            "vaultTicker": "alpSave",
            "assetComp": [
                {"assetTicker": "comp", "targetPercentage": 30},
                {"assetTicker": "aave", "targetPercentage": 40},
                {"assetTicker": "dydx", "targetPercentage": 30},
            ],
            "vaultAbi": [
                {
                    "inputs": [
                        {
                            "internalType": "address",
                            "name": "alpUsdcAddress_",
                            "type": "address",
                        }
                    ],
                    "stateMutability": "nonpayable",
                    "type": "constructor",
                },
                {
                    "inputs": [],
                    "name": "alpUsdcAddress",
                    "outputs": [
                        {"internalType": "address", "name": "", "type": "address"}
                    ],
                    "stateMutability": "view",
                    "type": "function",
                },
                {
                    "inputs": [
                        {"internalType": "address", "name": "user", "type": "address"}
                    ],
                    "name": "balanceOf",
                    "outputs": [
                        {"internalType": "uint256", "name": "usdc", "type": "uint256"},
                        {
                            "internalType": "uint256",
                            "name": "alpine",
                            "type": "uint256",
                        },
                    ],
                    "stateMutability": "view",
                    "type": "function",
                },
                {
                    "inputs": [
                        {"internalType": "address", "name": "user", "type": "address"},
                        {
                            "internalType": "uint256",
                            "name": "amountUsdc",
                            "type": "uint256",
                        },
                    ],
                    "name": "deposit",
                    "outputs": [],
                    "stateMutability": "nonpayable",
                    "type": "function",
                },
                {
                    "inputs": [],
                    "name": "usdcAddress",
                    "outputs": [
                        {"internalType": "address", "name": "", "type": "address"}
                    ],
                    "stateMutability": "view",
                    "type": "function",
                },
                {
                    "inputs": [
                        {"internalType": "address", "name": "user", "type": "address"},
                        {
                            "internalType": "uint256",
                            "name": "amountAlpUsdc",
                            "type": "uint256",
                        },
                    ],
                    "name": "withdraw",
                    "outputs": [],
                    "stateMutability": "nonpayable",
                    "type": "function",
                },
            ],
        }
    ]
