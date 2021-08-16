import logging
import sys
import os.path
sys.path.append("..")

from cron_utils import write_to_file, upload_to_s3, \
    TEMP_LOCAL_SAVE_DIR, S3_BUCKET_FOR_API_DATA
from scrapers.cefi_scraper import CeFiScraper

TEMP_LOCAL_SAVE_DIR = "test_results"
S3_BUCKET_FOR_API_DATA = "testbucketforapidata"

assets_of_interest = ["SPY", 
                      "QQQ",
                      "BND"]

scraper = CeFiScraper(assets=assets_of_interest)
try:
    scraper.collect_data()
except:
    logging.warning("Asset price collection failed.")

all_asset_data = scraper.data

for asset in assets_of_interest:
    written_file_path = write_to_file(all_asset_data[asset], file_name=asset, save_dir=TEMP_LOCAL_SAVE_DIR)
    logging.info("Written ", written_file_path)
    success = upload_to_s3(S3_BUCKET_FOR_API_DATA,
                           written_file_path,
                           "asset_data/" + \
                           f"{asset}/{os.path.basename(written_file_path)}")
    if not success:
        logging.warning(f"S3 upload failed for {asset}")
