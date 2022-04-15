import { BlockchainInfo } from "./types";
import { ethChainIds, polygonChainIds } from "./types";
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
  network_id: ethChainIds.goerli,
  proof_format: proofFormats.POA,
} as const;

export const ETH_MAINNET: BlockchainInfo = {
  name: blockchains.ETHEREUM,
  network: ethNetworks.MAINNET,
  network_id: ethChainIds.mainnet,
  proof_format: proofFormats.POW,
} as const;

export const POLYGON_MUMBAI: BlockchainInfo = {
  name: blockchains.POYLGON,
  network: polygonNetworks.MUMBAI,
  network_id: polygonChainIds.mumbai,
  proof_format: proofFormats.POS,
} as const;

export const POLYGON_MAINNET: BlockchainInfo = {
  name: blockchains.POYLGON,
  network: polygonNetworks.MAINNET,
  network_id: polygonChainIds.mainnet,
  proof_format: proofFormats.POS,
} as const;
