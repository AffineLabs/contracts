import { assert } from "chai";
import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { AllContracts, deployAll } from "./utils/deploy-all";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const ETH_NETWORK_NAME = 'ethGoerli'
const POLYGON_NETOWRK_NAME = 'polygonMumbai'

const CHECKPOINT_MANAGER = process.env.CHECKPOINT_MANAGER || "";
const FX_ROOT = process.env.FX_ROOT || "";
const FX_CHILD = process.env.FX_CHILD || "";
const ETH_USDC = process.env.ETH_USDC || "";
const POLYGON_USDC = process.env.POLYGON_USDC || "";
const POLYGON_ERC20_PREDICATE = process.env.POLYGON_ERC20_PREDICATE || "";
const ROOT_CHAIN_MANAGER = process.env.ROOT_CHAIN_MANAGER || "";

assert(CHECKPOINT_MANAGER !== "", "Checkpint Manager address must not be empty. Please set CHECKPOINT_MANAGER in the .env file.");
assert(FX_ROOT !== "", "Fx root address must not be empty. Please set FX_ROOT in the .env file.");
assert(FX_CHILD !== "", "Fx child address must not be empty. Please set FX_CHILD in the .env file.");
assert(ETH_USDC !== "", "ETH USDC Address is needed for testing. Please set ETH_USDC in the .env file.");
assert(POLYGON_USDC !== "", "Polygon USDC Address is needed for testing. Please set POLYGON_USDC in the .env file.");
assert(POLYGON_ERC20_PREDICATE !== "", "Polygon ERC20 predicate address is needed for testing. Please set POLYGON_ERC20_PREDICATE in the .env file.");
assert(ROOT_CHAIN_MANAGER !== "", "POS Portal RootChainManager address is needed for testing. Please set ROOT_CHAIN_MANAGER in the .env file.");

async function deployAllGoerliMumbai(): Promise<AllContracts> {
  const [governance, defender] = await ethers.getSigners()
  return await deployAll(
    governance,
    defender,
    ETH_NETWORK_NAME,
    POLYGON_NETOWRK_NAME,
    CHECKPOINT_MANAGER,
    ROOT_CHAIN_MANAGER,
    ETH_USDC,
    FX_ROOT,
    POLYGON_USDC,
    POLYGON_ERC20_PREDICATE,
    FX_CHILD,
  )
}

deployAllGoerliMumbai()
  .then((r) => {
    console.log('All Contracts\n', JSON.stringify(r));
    process.exit(0)
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
