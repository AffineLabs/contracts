from .base_api_scraper import BaseAPIScraper
import yfinance as yf

MAX_CALL_PER_SEC = 0.2


class YahooFinanceScraper(BaseAPIScraper):
    """docstring for YahooFinanceScraper"""
    def __init__(self, assets=[]):
        super(YahooFinanceScraper, self).__init__(assets=assets, max_calls_per_sec=MAX_CALL_PER_SEC)
        self.assets = assets

    def api_call_fn(self, asset_name):
        return yf.Ticker(asset_name).history(period="max")
