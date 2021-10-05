import json

import dotenv
from web3 import Web3

config = dotenv.dotenv_values(".env")
INFURA_API_KEY = config["INFURA_API_KEY"]


class Adapter:
    base_url = "https://min-api.cryptocompare.com/data/price"

    def __init__(self, input):
        # See the spec for how chainlink nodes request from external adaptors here
        # https://docs.chain.link/docs/developers/#requesting-data

        # {"id": 0, "data": {"network": "ETH", "tokens": ["0xfake1", "0xfake2"]}
        self.id = input.get("id", "1")
        self.request_data = input.get("data")

        if self.validate_request_data():
            self.create_request()
            self.result_success(self.result)
        else:
            self.result_error("No data provided")

    def validate_request_data(self):
        if self.request_data is None:
            return False
        if self.request_data == {}:
            return False
        return True

    def set_params(self):
        pass

    def create_request(self):
        # TODO(larryob): actually use the addresses passed in. Probably want to do
        # some address verification as well (i.e. error if any address is not in a list of tokens
        # that we want to return price for

        """
        testing with 
        curl -d '{"id": 0, "data": {"network": "ETH", "tokens": ["0x6B175474E89094C44Da98b954EedeAC495271d0F","0xdAC17F958D2ee523a2206206994597C13D831ec7"]}}'\
            -H "Content-Type: application/json" -X POST http://localhost:8080/
        Note that the data isn't actually used currently
        """
        w3 = Web3(Web3.HTTPProvider(f"https://kovan.infura.io/v3/{INFURA_API_KEY}"))

        cusdc_abi = []
        with open("cUSDC.json") as f:
            cusdc_abi = json.load(f)

        cusdc_addr = "0x4a92E71227D294F041BD82dd8f78591B75140d63"
        cusdc = w3.eth.contract(address="0x4a92E71227D294F041BD82dd8f78591B75140d63", abi=cusdc_abi)

        price_cusdc = cusdc.functions.exchangeRateCurrent().call()
        price_ausdc = 1

        ausdc_addr = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        self.result = {"prices": {cusdc_addr: price_cusdc, ausdc_addr: price_ausdc}}

    def result_success(self, data):
        self.result = {
            "jobRunID": self.id,
            "data": data,
            "result": self.result,
            "statusCode": 200,
        }

    def result_error(self, error):
        self.result = {
            "jobRunID": self.id,
            "status": "errored",
            "error": f"There was an error: {error}",
            "statusCode": 500,
        }
