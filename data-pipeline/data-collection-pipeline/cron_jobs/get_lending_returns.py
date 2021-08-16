import logging
import sys
import os.path
sys.path.append("..")

from cron_utils import write_to_file, upload_to_s3, \
    TEMP_LOCAL_SAVE_DIR, S3_BUCKET_FOR_API_DATA
from scrapers.defi_lending_scraper import DefiPulseScraper, SUPPORTED_PROTOCOLS

protocols_of_interest = SUPPORTED_PROTOCOLS

lending_price_data = DefiPulseScraper(protocols=protocols_of_interest).get_data()

jsonable_dict = {}
for protocol in protocols_of_interest:
    jsonable_dict[protocol] = lending_price_data[protocol]
    written_file_path = write_to_file(jsonable_dict[protocol], 
                                      file_name=protocol, 
                                      save_dir=TEMP_LOCAL_SAVE_DIR)
    logging.info("Written ", written_file_path)
    success = upload_to_s3(S3_BUCKET_FOR_API_DATA,
                            written_file_path,
                            "lending_protocols/" + \
                                f"{protocol}/{os.path.basename(written_file_path)}")
    if not success:
        logging.warning(f"S3 upload failed for {protocol}")