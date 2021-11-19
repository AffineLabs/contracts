import pytest
import sys
import pandas as pd
import datetime

sys.path.append("..")
from data_preprocessing_pipeline import preprocessing

# data to test lending protocol preprocessing
coin_price_df = pd.DataFrame(
    {
        "index": [
            datetime.date(2019, 9, 7),
            datetime.date(2019, 9, 8),
            datetime.date(2019, 9, 9),
            datetime.date(2019, 9, 10),
            datetime.date(2019, 9, 11),
            datetime.date(2019, 9, 12),
        ],
        "btc": [50500, 50600, 51000, 52000, 53600, 50000],
        "eth": [3500, 3600, 3650, 3400, 3432, 3300],
        "usdt": [0.98, 0.994, 1.01, 1.003, 1.02, 0.97],
        "usdc": [0.999, 0.985, 0.997, 1.001, 1.009, 0.999],
    }
).set_index("index")

lend_protocol_dfs = {
    "tick1": pd.DataFrame(
        {
            "index": [
                "2018-10-10 00:00:00",
                "2018-10-11 00:00:00",
                "2018-10-12 00:00:00",
            ],
            "lend_rate": [12.02, 10.0, 6.5],
        }
    ).set_index("index"),
    "tick2": pd.DataFrame(
        {
            "index": [
                "2019-09-10 00:00:00",
                "2019-09-11 00:00:00",
                "2019-09-12 00:00:00",
            ],
            "lend_rate": [10.02, 5, 9.5],
        }
    ).set_index("index"),
}

expected1 = {
    "lend_return": {"tick1": [12.02, 21, 6.5], "tick2": [10, 9, 8]},
}


class TestLendingDataPreprocessing:
    @pytest.mark.parametrize(
        "start_date, lend_protocol_dfs, coin_price_df, training_end_date, expected",
        [
            ("2018-10-12", lend_protocol_dfs, coin_price_df, "2018-10-15", expected1),
        ],
    )
    def test_preprocess_lending_data(
        self, start_date, lend_protocol_dfs, coin_price_df, training_end_date, expected
    ):

        lend_return_df = preprocessing.preprocess_lending_data(
            start_date, lend_protocol_dfs, coin_price_df, training_end_date
        )
        assert lend_return_df.to_dict("list") == expected["lend_return"]
