import { AdapterError, Validator } from '@chainlink/ea-bootstrap'
import { Config, ExecuteWithConfig, InputParameters } from '@chainlink/types'
import { ethers } from 'ethers'
import * as fs from 'fs'
import path from 'path'

// This should be filled in with a lowercase name corresponding to the API endpoint
export const supportedEndpoints = ['compound']

export const inputParameters: InputParameters = {
  chain: true,
  network: true,
  cusdc: true,
}

export const execute: ExecuteWithConfig<Config> = async (request, _, config) => {
  /**
   * Testing with 
   * curl -d '{"id": 0, "data": {"chain": "eth", "network": "kovan", "cusdc": "0x4a92E71227D294F041BD82dd8f78591B75140d63"}}'\
            -H "Content-Type: application/json" -X POST http://localhost:8080/
   */
  const validator = new Validator(request, inputParameters)
  if (validator.error) throw validator.error

  const jobRunID = validator.validated.id
  const { chain, network, cusdc } = validator.validated.data

  if (!['eth', 'polygon'].includes(chain))
    throw new AdapterError({ jobRunID, statusCode: 400, message: 'Chain must be eth or polygon' })

  if (chain == 'eth' && !['mainnet', 'kovan'].includes(network))
    throw new AdapterError({ jobRunID, statusCode: 400, message: `Bad network ${network}` })
  if (chain == 'polygon' && !['mainnet', 'mumbai'].includes(network))
    throw new AdapterError({ jobRunID, statusCode: 400, message: `Bad network ${network}` })

  // TODO: catch errors here
  const result = await getTokenInfo(chain, network, cusdc, config.apiKey || 'foo')

  return {
    jobRunID,
    result,
    data: { result },
    statusCode: 200,
  }
}

const getTokenInfo = async (
  chain: string,
  network: string,
  cusdc: string,
  apiKey: string,
): Promise<string> => {
  // TODO: get different addresses based on network
  const provider = new ethers.providers.JsonRpcProvider(`https://kovan.infura.io/v3/${apiKey}`)

  console.log({ chain, network })

  const abi = fs.readFileSync(path.resolve(__dirname, '../../src/abi/cUSDC.json'), 'utf8')
  const cusdcContract = new ethers.Contract(cusdc, abi, provider)

  // TODO: convert from big number
  const bigNumPrice = await cusdcContract.exchangeRateStored()
  return bigNumPrice.toString()
}
