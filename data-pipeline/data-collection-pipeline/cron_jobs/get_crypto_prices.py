import logging
import sys
import os.path

sys.path.append("..")

from cron_utils import (
    write_to_file,
    upload_to_s3,
    TEMP_LOCAL_SAVE_DIR,
    S3_BUCKET_FOR_API_DATA,
)
from scrapers.coingecko_scraper import CoinGeckoScraper

coins_of_interest = {
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "USDT": "tether",
    "USDC": "usd-coin",
    "BNB": "binancecoin",
    "UST": "terrausd",
    "DAI": "dai",
    "BSV": "bitcoin-cash-sv",
    "BCH": "bitcoin-cash",
    "ADA": "cardano",
    # "CEL": "celsius-degree-token",
    "LINK": "chainlink",
    # "DCR": "decred",
    "DOGE": "dogecoin",
    "EOS": "eos",
    "ETC": "ethereum-classic",
    # "HT": "huobi-token",
    "MIOTA": "iota",
    "LTC": "litecoin",
    "XMR": "monero",
    "NEO": "neo",
    "OKB": "okb",
    "XRP": "ripple",
    "XLM": "stellar",
    # "XTZ": "tezos",
    "THETA": "theta-token",
    "TRX": "tron",
    "VET": "vechain",
}

crypto_price_data = CoinGeckoScraper(assets=coins_of_interest.values()).get_data()

jsonable_dict = {}
for coin_ticker in coins_of_interest:
    jsonable_dict[coin_ticker] = crypto_price_data[coins_of_interest[coin_ticker]]
    written_file_path = write_to_file(
        jsonable_dict[coin_ticker], file_name=coin_ticker, save_dir=TEMP_LOCAL_SAVE_DIR
    )
    logging.info("Written ", written_file_path)
    success_cache = upload_to_s3(
        S3_BUCKET_FOR_API_DATA,
        written_file_path,
        "coin_data/" + f"{coin_ticker}/{os.path.basename(written_file_path)}",
    )

    if not success_cache:
        logging.warning(f"S3 upload failed for {coin_ticker}")

    # update the latest
    success_update = upload_to_s3(
        S3_BUCKET_FOR_API_DATA,
        written_file_path,
        "coin_data/" + f"{coin_ticker}/latest.csv",
    )

    if not success_update:
        logging.warning(f"S3 upload of latest.csv failed for {coin_ticker}")
