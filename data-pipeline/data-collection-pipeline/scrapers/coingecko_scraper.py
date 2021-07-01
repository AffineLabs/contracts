import datetime
import pandas as pd
from pycoingecko import CoinGeckoAPI

from .base_api_scraper import BaseAPIScraper

MAX_CALL_PER_SEC = 5


class CoinGeckoScraper(BaseAPIScraper):
    """docstring for CoinGeckoScraper."""
    def __init__(self, assets=[]):
        super(CoinGeckoScraper, self).__init__(assets=assets, max_calls_per_sec=MAX_CALL_PER_SEC)
        self.cg = CoinGeckoAPI()
    
    def api_call_fn(self, asset_name):
        data = self.cg.get_coin_market_chart_by_id(id=asset_name, vs_currency='usd', days='max')
        #TODO: We can also add market cap and volue data as they come free
        df = pd.DataFrame(data["prices"] ,columns=["timestamp", "price"])
        df["datetime"] = [datetime.datetime.utcfromtimestamp(t/1000.) for t in df.timestamp]

        return df
