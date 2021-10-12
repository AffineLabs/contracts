import json

import dotenv
from web3 import Web3

config = dotenv.dotenv_values(".env")
INFURA_API_KEY = config["INFURA_API_KEY"]


def get_info_polygon(network="mumbai"):
    ausdc_addr = "0x2271e3Fef9e15046d09E1d78a8FF038c691E9Cf9"
    price_ausdc = 1
    result = {"prices": {ausdc_addr: price_ausdc}}
    return result


def get_info_ethereum(network="kovan"):
    # TODO: change the addresses of the contracts based on the current network
    w3 = Web3(Web3.HTTPProvider(f"https://kovan.infura.io/v3/{INFURA_API_KEY}"))

    cusdc_abi = []
    with open("cUSDC.json") as f:
        cusdc_abi = json.load(f)

    cusdc_addr = "0x4a92E71227D294F041BD82dd8f78591B75140d63"
    cusdc = w3.eth.contract(address=cusdc_addr, abi=cusdc_abi)

    price_cusdc = cusdc.functions.exchangeRateCurrent().call()
    price_ausdc = 1

    ausdc_addr = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
    result = {"prices": {cusdc_addr: price_cusdc, ausdc_addr: price_ausdc}}
    return result


class Adapter:
    def __init__(self, input):
        # See the spec for how chainlink nodes request from external adaptors here
        # https://docs.chain.link/docs/developers/#requesting-data

        # {"id": 0, "data": {"network": "main", "tokens": ["0xfake1", "0xfake2"]}
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
            return True
        return True

    def set_params(self):
        pass

    def create_request(self):
        # TODO(larryob): actually use the addresses passed in. Probably want to do
        # some address verification as well (i.e. error if any address is not in a list of tokens
        # that we want to return price for

        """
        testing with 
        curl -d '{"id": 0, "data": {"chain": "eth", "network": "main" }}'\
            -H "Content-Type: application/json" -X POST http://localhost:8080/
        """

        chain = self.request_data["chain"]
        network = self.request_data["network"]

        if chain == "eth":
            self.result = get_info_ethereum(network)
            return
        elif chain == "polygon":
            self.result = get_info_polygon(network)
            return
        else:
            # TODO: fix this. result_success is called afterwards
            self.result_error("Chain not currently supported")
            return

    def result_success(self, data):
        # Chainlink node expects to find data under the "data" field of the response
        # In "copy" core adapter of chainlink node, threre is an implicit
        # "data" prepended to the "copyPath" value. So if reponse json is {"data": {"foo": "bar"}}
        # my copyPath value is ["foo", "bar"]
        self.result = {
            "jobRunID": self.id,
            "data": self.result,
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
