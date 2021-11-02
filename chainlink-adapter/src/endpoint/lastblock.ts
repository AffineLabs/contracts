import { AdapterError, Validator } from '@chainlink/ea-bootstrap'
import { Config, ExecuteWithConfig, InputParameters } from '@chainlink/types'
import { ethers } from 'ethers'
import * as fs from 'fs'
import path from 'path'

// This should be filled in with a lowercase name corresponding to the API endpoint
export const supportedEndpoints = ['lastblock']

export const inputParameters: InputParameters = {
  chainId: true,
  stagingAddress: true,
}

interface chainIdMap {
  [chainId: number]: string
}

export const execute: ExecuteWithConfig<Config> = async (request, _, config) => {
  /**
   * Testing with 
   * curl -d '{"id": 0, "data": {"chainId": 42, "stagingAddress": "0x8635Ec536F0125cf6B766ed67B4A37Dcb76eb508", "endpoint": "lastblock"}}'\
            -H "Content-Type: application/json" -X POST http://localhost:8080/
   */
  const validator = new Validator(request, inputParameters)
  if (validator.error) throw validator.error

  const jobRunID = validator.validated.id
  const { chainId, stagingAddress } = validator.validated.data

  // eth mainnet, eth kovan, polygon mainnet, polygon mumbai
  if (![1, 42, 137, 80001].includes(chainId))
    throw new AdapterError({
      jobRunID,
      statusCode: 400,
      message: `Chain with id ${chainId} not supported`,
    })

  const chainIdToName: chainIdMap = { 1: 'mainnet', 42: 'kovan' }
  const name = chainIdToName[chainId]

  // TODO: Switch over to alchemy and support polygon
  const provider = new ethers.providers.JsonRpcProvider(
    `https://${name}.infura.io/v3/${config.apiKey}`,
  )

  const abi = fs.readFileSync(path.resolve(__dirname, '../../src/abi/stagingContract.json'), 'utf8')

  const stagingContract = new ethers.Contract(stagingAddress, abi, provider)
  const result = (await stagingContract.lastBlock()).toString()

  console.log({ result })

  return {
    jobRunID,
    result,
    data: { result },
    statusCode: 200,
  }
}
