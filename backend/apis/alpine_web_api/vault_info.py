def list_all_vault_metadata():
    return [
        {
            "vaultName": "Alpine Save",
            "vaultAddress": "0x6076f3011c987A19a04e2B6a37A96Aed1ee01492",
            "vaultTicker": "alpSave",
            "vaultApy": 5.2,
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
        },
        {
            "vaultName": "USDC",
            "vaultAddress": "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
            "vaultTicker": "usdc",
            "assetComp": [],
            "vaultAbi": [
                {
                    "inputs": [
                        {
                            "internalType": "address",
                            "name": "_proxyTo",
                            "type": "address",
                        }
                    ],
                    "stateMutability": "nonpayable",
                    "type": "constructor",
                },
                {
                    "anonymous": False,
                    "inputs": [
                        {
                            "indexed": False,
                            "internalType": "address",
                            "name": "_new",
                            "type": "address",
                        },
                        {
                            "indexed": False,
                            "internalType": "address",
                            "name": "_old",
                            "type": "address",
                        },
                    ],
                    "name": "ProxyOwnerUpdate",
                    "type": "event",
                },
                {
                    "anonymous": False,
                    "inputs": [
                        {
                            "indexed": True,
                            "internalType": "address",
                            "name": "_new",
                            "type": "address",
                        },
                        {
                            "indexed": True,
                            "internalType": "address",
                            "name": "_old",
                            "type": "address",
                        },
                    ],
                    "name": "ProxyUpdated",
                    "type": "event",
                },
                {"stateMutability": "payable", "type": "fallback"},
                {
                    "inputs": [],
                    "name": "IMPLEMENTATION_SLOT",
                    "outputs": [
                        {"internalType": "bytes32", "name": "", "type": "bytes32"}
                    ],
                    "stateMutability": "view",
                    "type": "function",
                },
                {
                    "inputs": [],
                    "name": "OWNER_SLOT",
                    "outputs": [
                        {"internalType": "bytes32", "name": "", "type": "bytes32"}
                    ],
                    "stateMutability": "view",
                    "type": "function",
                },
                {
                    "inputs": [],
                    "name": "implementation",
                    "outputs": [
                        {"internalType": "address", "name": "", "type": "address"}
                    ],
                    "stateMutability": "view",
                    "type": "function",
                },
                {
                    "inputs": [],
                    "name": "proxyOwner",
                    "outputs": [
                        {"internalType": "address", "name": "", "type": "address"}
                    ],
                    "stateMutability": "view",
                    "type": "function",
                },
                {
                    "inputs": [],
                    "name": "proxyType",
                    "outputs": [
                        {
                            "internalType": "uint256",
                            "name": "proxyTypeId",
                            "type": "uint256",
                        }
                    ],
                    "stateMutability": "pure",
                    "type": "function",
                },
                {
                    "inputs": [
                        {
                            "internalType": "address",
                            "name": "newOwner",
                            "type": "address",
                        }
                    ],
                    "name": "transferProxyOwnership",
                    "outputs": [],
                    "stateMutability": "nonpayable",
                    "type": "function",
                },
                {
                    "inputs": [
                        {
                            "internalType": "address",
                            "name": "_newProxyTo",
                            "type": "address",
                        },
                        {"internalType": "bytes", "name": "data", "type": "bytes"},
                    ],
                    "name": "updateAndCall",
                    "outputs": [],
                    "stateMutability": "payable",
                    "type": "function",
                },
                {
                    "inputs": [
                        {
                            "internalType": "address",
                            "name": "_newProxyTo",
                            "type": "address",
                        }
                    ],
                    "name": "updateImplementation",
                    "outputs": [],
                    "stateMutability": "nonpayable",
                    "type": "function",
                },
                {"stateMutability": "payable", "type": "receive"},
            ],
        },
    ]
