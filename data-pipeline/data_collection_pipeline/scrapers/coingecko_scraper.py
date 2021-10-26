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
        # data[x] is a list of (timestamp, x)
        # zip(*) unzips the tuples
        timestamps, prices = zip(*data["prices"])
        _, market_caps = zip(*data["market_caps"])
        _, total_volumes = zip(*data["total_volumes"])

        df = pd.DataFrame(
            {
                "timestamp": timestamps,
                "price": prices,
                "datetime": [
                    datetime.datetime.utcfromtimestamp(t / 1000.0) for t in timestamps
                ],
                "market_cap": market_caps,
                "trading_volume_24h": total_volumes,
            }
        )
        return df
