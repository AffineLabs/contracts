import asyncio
import pandas as pd
import logging
import sys
import os.path
sys.path.append("..")

from gql.transport.aiohttp import AIOHTTPTransport
from gql import Client, gql

from itertools import chain, repeat

from cron_utils import write_to_file, upload_to_s3, \
    TEMP_LOCAL_SAVE_DIR, S3_BUCKET_FOR_API_DATA

uniswap_token_pair_data = [
    ('0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc', 'Uniswap-v2-USDC-WETH', 0.3), 
    ('0x0d4a11d5eeaac28ec3f61d100daf4d40471f1852', 'Uniswap-v2-WETH-USDT', 0.3), 
    ('0xbb2b8038a1640196fbe3e38816f3e67cba72d940', 'Uniswap-v2-WBTC-WETH', 0.3), 
    ('0x3041cbd36888becc7bbcbc0045e3b1f144466f5f', 'Uniswap-v2-USDC-USDT', 0.05), 
    ('0xa478c2975ab1ea89e8196811f51a7b7ade33eb11', 'Uniswap-v2-DAI-WETH', 0.3), 
    ('0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5', 'Uniswap-v2-DAI-USDC', 0.05), 
    ('0xb20bd5d04be54f870d5c0d3ca85d82b34b836405', 'Uniswap-v2-DAI-USDT', 0.05)
]

sushi_token_pair_data = [
    ('0xceff51756c56ceffca006cd410b03ffc46dd3a58', 'Sushiswap-WBTC-WETH', 0.25),
    ('0x397ff1542f962076d0bfe58ea045ffa2d347aca0', 'Sushiswap-USDC-WETH', 0.25),
    ('0x06da0fd433c1a5d7a4faa01111c044910a184553', 'Sushiswap-WETH-USDT', 0.25), 
    ('0xc3d03e4f041fd4cd388c549ee2a29a9e5075882f', 'Sushiswap-DAI-WETH', 0.25)
]

uniswap_url = "https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v2"
sushiswap_url = "https://api.thegraph.com/subgraphs/name/zippoxer/sushiswap-subgraph-fork"

async def collect_data(url, address):

    transport = AIOHTTPTransport(url=url)
    overall_data = []
    # Using `async with` on the client will start a connection on the transport
    # and provide a `session` variable to execute queries on this connection
    async with Client(
        transport=transport, fetch_schema_from_transport=True,
    ) as session:
        while True:
            # Execute single query
            query = gql("""
                query {
                  pairDayDatas (first:1000 skip:""" + str(len(overall_data)) + """ where: {pairAddress: "ADDR"}) {
                    date
                    reserveUSD
                    dailyVolumeUSD
                  }
                }
            """.replace("ADDR", address)
            )

            result = await session.execute(query)
            overall_data.extend(result['pairDayDatas'])
            print('Call!', len(result['pairDayDatas']))
            if len(result['pairDayDatas']) < 1000:
                break
    return overall_data


async def main():
    amm_pool_iterator = chain(
        zip(uniswap_token_pair_data, repeat(uniswap_url)), 
        zip(sushi_token_pair_data, repeat(sushiswap_url))
    )
    for (addr, name, fee_tier), url in amm_pool_iterator:
        all_results = await collect_data(url, addr)
        results = pd.DataFrame.from_records(all_results)
        results.date = pd.to_datetime(results.date, unit='s')
        results = results.set_index('date')
        results['daily_return'] = (0.01 * fee_tier) * \
            (pd.to_numeric(results['dailyVolumeUSD'], errors='coerce') / \
             pd.to_numeric(results['reserveUSD'], errors='coerce'))
        results['apy'] = ((1.0 + results['daily_return']) ** 365) - 1.0
        written_file_path = write_to_file(results, file_name=name, save_dir=TEMP_LOCAL_SAVE_DIR)
        logging.info("Written ", written_file_path)
        success = upload_to_s3(S3_BUCKET_FOR_API_DATA,
                               written_file_path,
                               "amm_liquidity_pool/" + \
                               f"{name.split('-')[0]}/{name}/{os.path.basename(written_file_path)}")

if __name__ == '__main__':
    asyncio.run(main())