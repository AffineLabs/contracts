import { BlockchainInfo } from "./types";

enum blockchains {
  ETHEREUM = "Ethereum",
  POYLGON = "Polygon",
}

enum ethNetworks {
  MAINNET = "Mainnet",
  GOERLI = "Goerli",
}

enum polygonNetworks {
  MAINNET = "Mainnet",
  MUMBAI = "Mumbai",
}

enum proofFormats {
  POA = "POA",
  POS = "POS",
  POW = "POW",
}

export const ETH_GOERLI: BlockchainInfo = {
  name: blockchains.ETHEREUM,
  network: ethNetworks.GOERLI,
  proof_format: proofFormats.POA,
} as const;

export const ETH_MAINNET: BlockchainInfo = {
  name: blockchains.ETHEREUM,
  network: ethNetworks.MAINNET,
  proof_format: proofFormats.POW,
} as const;

export const POLYGON_MUMBAI: BlockchainInfo = {
  name: blockchains.POYLGON,
  network: polygonNetworks.MUMBAI,
  proof_format: proofFormats.POS,
} as const;

export const POLYGON_MAINNET: BlockchainInfo = {
  name: blockchains.POYLGON,
  network: polygonNetworks.MAINNET,
  proof_format: proofFormats.POS,
} as const;
