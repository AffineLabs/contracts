import { BlockchainInfo } from "./types";

export const ETH_GOERLI: BlockchainInfo = {
  name: "Ethereum",
  network: "Goerli",
  proof_format: "POA",
} as const;

export const ETH_MAINNET: BlockchainInfo = {
  name: "Ethereum",
  network: "Mainnet",
  proof_format: "POW",
} as const;

export const POLYGON_MUMBAI: BlockchainInfo = {
  name: "Polygon",
  network: "Goerli",
  proof_format: "POS",
} as const;

export const POLYGON_MAINNET: BlockchainInfo = {
  name: "Polygon",
  network: "Mainnet",
  proof_format: "POS",
} as const;
