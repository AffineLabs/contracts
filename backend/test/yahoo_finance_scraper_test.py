from ..scrapers.yahoo_finance_scraper import YahooFinanceScraper

def test_get_data():
    yf = YahooFinanceScraper(assets=["SPY"])
    data = yf.get_data()
    # fix :P
    assert(len(data["SPY"]) > 100)
