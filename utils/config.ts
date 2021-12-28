import { assert } from "chai";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { address } from "./types";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const ETH_USDC = process.env.ETH_USDC || "";
const POLYGON_USDC = process.env.POLYGON_USDC || "";
const POLYGON_ERC20_PREDICATE = process.env.POLYGON_ERC20_PREDICATE || "";
const ROOT_CHAIN_MANAGER = process.env.ROOT_CHAIN_MANAGER || "";
const DEFENDER = process.env.DEFENDER || "";
const ETH_WORMHOLE = process.env.ETH_WORMHOLE || "";
const POLYGON_WORMHOLE = process.env.POLYGON_WORMHOLE || "";

assert(ETH_USDC !== "", "ETH USDC Address is needed for testing. Please set ETH_USDC in the .env file.");
assert(POLYGON_USDC !== "", "Polygon USDC Address is needed for testing. Please set POLYGON_USDC in the .env file.");
assert(
  POLYGON_ERC20_PREDICATE !== "",
  "Polygon ERC20 predicate address is needed for testing. Please set POLYGON_ERC20_PREDICATE in the .env file.",
);

assert(DEFENDER !== "", "Defender address is needed for testing. Please set DEFENDER in the .env file.");
assert(ETH_WORMHOLE !== "" && POLYGON_WORMHOLE !== "", "Add wormhole addresses.");
assert(ROOT_CHAIN_MANAGER !== "", "Set ETH chain manager");

export interface Config {
  l1ChainManager: address;
  l1USDC: address;
  l2USDC: address;
  l2ERC20Predicate: address;
  defender: address;
  l1worm: address;
  l2worm: address;
}
export const config: Config = {
  l1ChainManager: ROOT_CHAIN_MANAGER,
  l1USDC: ETH_USDC,
  l2USDC: POLYGON_USDC,
  l2ERC20Predicate: POLYGON_ERC20_PREDICATE,
  defender: DEFENDER,
  l1worm: ETH_WORMHOLE,
  l2worm: POLYGON_WORMHOLE,
};
