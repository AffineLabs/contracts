from .yahoo_finance_scraper import YahooFinanceScraper

scraping_engines = {
    "yahoo-finance" : YahooFinanceScraper
}


class CeFiScraper(object):
    """docstring for CeFiScraper"""
    def __init__(self, assets=[], engine_name="yahoo-finance"):
        super(CeFiScraper, self).__init__()
        self.assets = assets
        self.engine_name = engine_name
        self.scraper_class = scraping_engines.get(self.engine_name, "yahoo-finance")

        # initiate scraper
        self.scraper = self.scraper_class(assets=assets)

    def collect_data(self):
        self.data = self.scraper.get_data()

    def upload_data_db(self):
        pass

    def run(self):
        self.collect_data()
        self.upload_data_db()
        print("done")
