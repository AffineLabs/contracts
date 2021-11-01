import { Requester, util } from '@chainlink/ea-bootstrap'
import { Config } from '@chainlink/types'

export const NAME = 'ALCHEMY' // This should be filled in with a name corresponding to the data provider using UPPERCASE and _underscores_.

export const makeConfig = (prefix?: string): Config => {
  const config = Requester.getDefaultConfig(prefix)

  config.apiKey = util.getRequiredEnv('INFURA_API_KEY')
  console.log('api key...', config.apiKey)
  config.defaultEndpoint = 'compound'
  return config
}
