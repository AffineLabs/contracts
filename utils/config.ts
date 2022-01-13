import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { address } from "./types";

dotenvConfig({ path: resolve(__dirname, "./.env") });

// Hardcoded Mumbai Addresses
const ETH_USDC = "0x077ffc33b12ac8CFfF5B9F71658bc6575E16a113";
const POLYGON_USDC = "0x5fD6A096A23E95692E37Ec7583011863a63214AA";
const POLYGON_ERC20_PREDICATE = "0x37c3bfC05d5ebF9EBb3FF80ce0bd0133Bf221BC8";
const ROOT_CHAIN_MANAGER = "0xBbD7cBFA79faee899Eaf900F13C9065bF03B1A74";
const ETH_WORMHOLE = "0x706abc4E45D419950511e474C7B9Ed348A4a716c";
const POLYGON_WORMHOLE = "0x0CBE91CF822c73C2315FB05100C2F714765d5c20";

export interface Config {
  l1ChainManager: address;
  l1USDC: address;
  l2USDC: address;
  l2ERC20Predicate: address;
  l1worm: address;
  l2worm: address;
}
export const config: Config = {
  l1ChainManager: ROOT_CHAIN_MANAGER,
  l1USDC: ETH_USDC,
  l2USDC: POLYGON_USDC,
  l2ERC20Predicate: POLYGON_ERC20_PREDICATE,
  l1worm: ETH_WORMHOLE,
  l2worm: POLYGON_WORMHOLE,
};

export interface RebalanceConfig {
  ethAlchemyURL: string;
  polygonAlchemyURL: string;
  mnemonic: string;
  l1VaultAddr: address;
  l2VaultAddr: address;
}

const ethAlchemyURL = process.env.ALCHEMY_ETH_KEY ? `https://eth-goerli.alchemyapi.io/v2/${process.env.ALCHEMY_ETH_KEY}` || "";
const polygonAlchemyURL = process.env.ALCHEMY_POLYGON_KEY ? `https://polygon-mumbai.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_KEY}` || "";
const mnemonic = process.env.MNEMONIC || "";
const l1VaultAddr = "0xe05F99bd5B4f755Caf9bd5E46bDd1468F9D650Fa";
const l2VaultAddr = "0xd914975c045f2d29770C11656bCe4236aF3Dfe19";

export const REBALANCE_CONFIG: RebalanceConfig = {
  ethAlchemyURL,
  polygonAlchemyURL,
  mnemonic,
  l1VaultAddr,
  l2VaultAddr,
};

Object.entries(REBALANCE_CONFIG).map(([key, val]) => {
  if (val === "") throw Error(`${key} may not be empty. Check .env file`);
});
