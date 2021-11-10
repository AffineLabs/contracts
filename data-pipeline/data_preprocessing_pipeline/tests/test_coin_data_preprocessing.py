import pytest
import sys
import pandas as pd

sys.path.append("..")
from data_preprocessing_pipeline import preprocessing


# data to test coin price preprocessing
coin_dfs = {
    "tick1": pd.DataFrame(
        {
            "index": [
                "2018-10-10 00:00:00",
                "2018-10-11 00:00:00",
                "2018-10-12 00:00:00",
            ],
            "price": [12.02, 21, 6.5],
            "trading_volume_24h": [100, 0, 20],
            "market_cap": [100, 10, 0],
            "timestamp": [12345, 23415, 12263],
        }
    ).set_index("index"),
    "tick2": pd.DataFrame(
        {
            "index": [
                "2019-09-10 00:00:00",
                "2019-09-11 00:00:00",
                "2019-09-12 00:00:00",
            ],
            "price": [10.02, 5, 9.5],
            "trading_volume_24h": [120, 10, 20],
            "market_cap": [100, 40, 40],
            "timestamp": [145, 3415, 1263],
        }
    ).set_index("index"),
}

expected1 = {
    "price": {
        "tick1": [12.02, 21, 6.5],
    },
    "trading_volume_24h": {
        "tick1": [100, 0, 20],
    },
    "market_cap": {
        "tick1": [100, 10, 0],
    },
}

expected2 = {
    "price": {
        "tick1": [],
        "tick2": [],
    },
    "trading_volume_24h": {
        "tick1": [],
        "tick2": [],
    },
    "market_cap": {
        "tick1": [],
        "tick2": [],
    },
}


class TestCoinDataPreprocessing:
    @pytest.mark.parametrize(
        "start_date, coin_dfs, expected",
        [("2018-10-12", coin_dfs, expected1), ("2020-11-12", coin_dfs, expected2)],
    )
    def test_preprocess_coin_data(self, start_date, coin_dfs, expected):
        (
            coin_price_df,
            coin_market_cap_df,
            coin_trading_volume_df,
        ) = preprocessing.preprocess_coin_data(
            start_date, coin_dfs, take_rolling_mean=False
        )

        assert coin_price_df.to_dict("list") == expected["price"]
        assert coin_market_cap_df.to_dict("list") == expected["market_cap"]
        assert coin_trading_volume_df.to_dict("list") == expected["trading_volume_24h"]
