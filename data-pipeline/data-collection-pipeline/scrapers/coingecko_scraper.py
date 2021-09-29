import datetime
import pandas as pd
from pycoingecko import CoinGeckoAPI

from .base_api_scraper import BaseAPIScraper

MAX_CALL_PER_SEC = 5


class CoinGeckoScraper(BaseAPIScraper):
    """docstring for CoinGeckoScraper."""

    def __init__(self, assets=[]):
        super(CoinGeckoScraper, self).__init__(
            assets=assets, max_calls_per_sec=MAX_CALL_PER_SEC
        )
        self.cg = CoinGeckoAPI()

    def api_call_fn(self, asset_name):
        data = self.cg.get_coin_market_chart_by_id(
            id=asset_name, vs_currency="usd", days="max"
        )
        # data[prices] is a list of (timestamp, price)
        df = pd.DataFrame(data["prices"], columns=["timestamp", "price"])
        df["datetime"] = [
            datetime.datetime.utcfromtimestamp(t / 1000.0) for t in df.timestamp
        ]
        df["market_cap"] = [market_cap for _, market_cap in data["market_caps"]]
        df["trading_volume_24h"] = [
            total_volume for _, total_volume in data["total_volumes"]
        ]

        return df
