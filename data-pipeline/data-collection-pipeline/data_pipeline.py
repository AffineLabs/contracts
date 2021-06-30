# run this once every hour

from scrapers.cefi_scraper import CeFiScraper

# TODO: add all of them
scrapers = {
    "cefi": CeFiScraper
}


for sc in scrapers:
    scraper = scrapers.get(sc)()
    scraper.run()