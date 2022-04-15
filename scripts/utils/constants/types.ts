export interface BlockchainInfo {
  name: string;
  network: string;
  network_id: number;
  proof_format: string;
}

export const ethChainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};
export type ethNetwork = keyof typeof ethChainIds;

export const polygonChainIds = {
  mainnet: 137,
  mumbai: 80001,
};
export type polygonNetwork = keyof typeof polygonChainIds;
