asset_level_portfolios = {
    "lendingProtocols": {
        "aave": 0.25,
        "comp": 0.15,
        "dydx": 0.25,
        "definer": 0.1,
        "anc": 0.25,
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
    "alpSave": {
        "lendingProtocols": 1.0,
        "btcEth": 0.0,
        "altCoins": 0.0,
    },
    "alpBal": {
        "lendingProtocols": 0.8,
        "btcEth": 0.2,
        "altCoins": 0.0,
    },
    "alpAggr": {
        "lendingProtocols": 0.2,
        "btcEth": 0.5,
        "altCoins": 0.3,
    },
}


portfolio_base = {
    "alpSave": {
        "fullname": "Alpine Save",
        "description": "Invests in only in lending protocols for stable yields.",
        "lendingProtocols": {
            "portfolioPercentage": 100.0,
            "assets": [
                {"ticker": "aave", "fullname": "AAVE"},
                {"ticker": "comp", "fullname": "Compound"},
                {"ticker": "dydx", "fullname": "dYdX"},
                {"ticker": "definer", "fullname": "DeFiner"},
                {"ticker": "anc", "fullname": "Anchor"},
            ],
        },
        "btcEth": {
            "portfolioPercentage": 0.0,
            "assets": [
                {"ticker": "btc", "fullname": "Bitcoin"},
                {"ticker": "eth", "fullname": "Ethereum"},
            ],
        },
        "altCoins": {
            "portfolioPercentage": 0.0,
            "assets": [
                {"ticker": "xrp", "fullname": "Ripple"},
                {"ticker": "bch", "fullname": "Bitcoin Cash"},
                {"ticker": "eos", "fullname": "Eos"},
                {"ticker": "xlm", "fullname": "Stellar"},
                {"ticker": "ltc", "fullname": "Litecoin"},
                {"ticker": "bsv", "fullname": "Bitcoin SV"},
                {"ticker": "trx", "fullname": "Tron"},
                {"ticker": "ada", "fullname": "Cardano"},
                {"ticker": "miota", "fullname": "Iota"},
                {"ticker": "xmr", "fullname": "Monero"},
            ],
        },
    },
    "alpBal": {
        "fullname": "Alpine Balanced",
        "description": "Invests 80% in lending protocols for stable yields and 20% in Bitcoin and Ethereum.",
        "lendingProtocols": {
            "portfolioPercentage": 80.0,
            "assets": [
                {"ticker": "aave", "fullname": "AAVE"},
                {"ticker": "comp", "fullname": "Compound"},
                {"ticker": "dydx", "fullname": "dYdX"},
                {"ticker": "definer", "fullname": "DeFiner"},
                {"ticker": "anc", "fullname": "Anchor"},
            ],
        },
        "btcEth": {
            "portfolioPercentage": 20.0,
            "assets": [
                {"ticker": "btc", "fullname": "Bitcoin"},
                {"ticker": "eth", "fullname": "Ethereum"},
            ],
        },
        "altCoins": {
            "portfolioPercentage": 0.0,
            "assets": [
                {"ticker": "xrp", "fullname": "Ripple"},
                {"ticker": "bch", "fullname": "Bitcoin Cash"},
                {"ticker": "eos", "fullname": "Eos"},
                {"ticker": "xlm", "fullname": "Stellar"},
                {"ticker": "ltc", "fullname": "Litecoin"},
                {"ticker": "bsv", "fullname": "Bitcoin SV"},
                {"ticker": "trx", "fullname": "Tron"},
                {"ticker": "ada", "fullname": "Cardano"},
                {"ticker": "miota", "fullname": "Iota"},
                {"ticker": "xmr", "fullname": "Monero"},
            ],
        },
    },
    "alpAggr": {
        "fullname": "Alpine Aggressive",
        "description": "Invests 20% in lending protocols for stable yields, 50% in "
        "Bitcoin and Ethereum, and 30% in Alt Coins.",
        "lendingProtocols": {
            "portfolioPercentage": 20.0,
            "assets": [
                {"ticker": "aave", "fullname": "AAVE"},
                {"ticker": "comp", "fullname": "Compound"},
                {"ticker": "dydx", "fullname": "dYdX"},
                {"ticker": "definer", "fullname": "DeFiner"},
                {"ticker": "anc", "fullname": "Anchor"},
            ],
        },
        "btcEth": {
            "portfolioPercentage": 50.0,
            "assets": [
                {"ticker": "btc", "fullname": "Bitcoin"},
                {"ticker": "eth", "fullname": "Ethereum"},
            ],
        },
        "altCoins": {
            "portfolioPercentage": 30.0,
            "assets": [
                {"ticker": "xrp", "fullname": "Ripple"},
                {"ticker": "bch", "fullname": "Bitcoin Cash"},
                {"ticker": "eos", "fullname": "Eos"},
                {"ticker": "xlm", "fullname": "Stellar"},
                {"ticker": "ltc", "fullname": "Litecoin"},
                {"ticker": "bsv", "fullname": "Bitcoin SV"},
                {"ticker": "trx", "fullname": "Tron"},
                {"ticker": "ada", "fullname": "Cardano"},
                {"ticker": "miota", "fullname": "Iota"},
                {"ticker": "xmr", "fullname": "Monero"},
            ],
        },
    },
}
