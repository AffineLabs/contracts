import json
import os
import requests

import pandas as pd

from datetime import date

today = date.today()

API_KEY = os.environ.get("DEFIPULSE_API_KEY")
API_URL = f"https://data-api.defipulse.com/api/v1/defipulse/api/getLendingHistory?api-key={API_KEY}"

SUPPORTED_PROTOCOLS = ('aave', 'c.r.e.a.m.-finance', 'compound', 'definer', 'dydx', 'maker')

class DefiPulseScraper:
    """Scrape DefiPulse API to get the historical rate data from different protocols"""
    def __init__(self, protocols=SUPPORTED_PROTOCOLS):
        self.protocols = protocols

    def _get_cached_data(self):
        today = date.today()
        CACHED_HISTORY = f".cache/defi-pulse-lending-history-{today}.json"
        if not os.path.exists(CACHED_HISTORY):
            os.makedirs('.cache', exist_ok=True)
            req = requests.get(API_URL)
            if req.text.startswith("Wrong api-key provided!"):
                raise ValueError("Wrong API key provided for Defi-pulse, " + \
                                 "please check your $DEFIPULSE_API_KEY env variable.")
            read_json = req.json()
            serialized_data = json.dumps(read_json)
            with open(CACHED_HISTORY, "w") as f:
                f.write(serialized_data)

        return pd.read_json(CACHED_HISTORY)

    def get_data(self):
        protocols = self.protocols
        result_json = self._get_cached_data()
        protocol_data_dictionary = {protocol_name: {} for protocol_name in protocols}
        result_json = result_json[result_json.timestamp != 'undefined']

        for _, row in result_json.iterrows():
            row_time = pd.to_datetime(row.timestamp, unit='s')
            for protocol in protocols:
                protocol_data_dictionary[protocol][row_time] = {
                    'lend_rate': row.lend_rates.get(protocol),
                    'borrow_rate': row.borrow_rates.get(protocol),
                }

        protocol_data_dict = {}
        for protocol in protocols:
            protocol_data_dict[protocol] = pd.DataFrame.from_dict(
                protocol_data_dictionary[protocol], orient='index')
            protocol_data_dict[protocol].dropna()

        return protocol_data_dict