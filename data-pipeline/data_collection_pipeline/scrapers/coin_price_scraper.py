from coingecko_scraper import CoinGeckoScraper

scraping_engines = {
    "coingecko" : CoinGeckoScraper
}
class CoinPriceScraper(object):
    """docstring for CoinPriceScraper."""
    def __init__(self, asset_names=[], engine="coingecko"):
        super(CoinPriceScraper, self).__init__()
        self.asset_names = asset_names
        