import time

class BaseAPIScraper(object):
    """Base of all api based scraper"""
    def __init__(self, assets=[], max_calls_per_sec=0.2):
        self.assets = assets
        self.max_calls_per_sec = max_calls_per_sec

    def api_call_fn(self, asset_name):
        raise NotImplementedError("Must implement api call function")
    
    def get_data(self):
        asset_data_dict = {}
        for asset_name in self.assets:
            try:
                asset_data_dict[asset_name] = self.api_call_fn(asset_name)
            except Exception as e:
                #TODO: log in sentry
                print(e)
                print(f"FAILED TO SCRAPE ASSET: {asset_name}")
            #TODO: exponential backoff if retried
            time.sleep(1.0 / self.max_calls_per_sec)

        return asset_data_dict
