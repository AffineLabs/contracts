import { assert } from "chai";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const CHECKPOINT_MANAGER = process.env.CHECKPOINT_MANAGER || "";
const FX_ROOT = process.env.FX_ROOT || "";
const FX_CHILD = process.env.FX_CHILD || "";
const ETH_USDC = process.env.ETH_USDC || "";
const POLYGON_USDC = process.env.POLYGON_USDC || "";
const POLYGON_ERC20_PREDICATE = process.env.POLYGON_ERC20_PREDICATE || "";
const ROOT_CHAIN_MANAGER = process.env.ROOT_CHAIN_MANAGER || "";
const CREATE2DEPLOYER = process.env.CREATE2DEPLOYER || "";
const DEFENDER = process.env.DEFENDER || "";
const ETH_WORMHOLE = process.env.ETH_WORMHOLE || "";
const POLYGON_WORMHOLE = process.env.POLYGON_WORMHOLE || "";

assert(
  CHECKPOINT_MANAGER !== "",
  "Checkpoint Manager address must not be empty. Please set CHECKPOINT_MANAGER in the .env file.",
);
assert(FX_ROOT !== "", "Fx root address must not be empty. Please set FX_ROOT in the .env file.");
assert(FX_CHILD !== "", "Fx child address must not be empty. Please set FX_CHILD in the .env file.");
assert(ETH_USDC !== "", "ETH USDC Address is needed for testing. Please set ETH_USDC in the .env file.");
assert(POLYGON_USDC !== "", "Polygon USDC Address is needed for testing. Please set POLYGON_USDC in the .env file.");
assert(
  POLYGON_ERC20_PREDICATE !== "",
  "Polygon ERC20 predicate address is needed for testing. Please set POLYGON_ERC20_PREDICATE in the .env file.",
);
assert(
  CREATE2DEPLOYER !== "",
  "Create2 deployer address is needed for testing. Please set CREATE2DEPLOYER in the .env file.",
);
assert(DEFENDER !== "", "Defender address is needed for testing. Please set DEFENDER in the .env file.");
assert(ETH_WORMHOLE !== "" && POLYGON_WORMHOLE !== "", "Add wormhole addresses.");

const config = {
  checkpointManager: CHECKPOINT_MANAGER,
  l1ChainManager: ROOT_CHAIN_MANAGER,
  l1USDC: ETH_USDC,
  l1FxTunnel: FX_ROOT,
  l2USDC: POLYGON_USDC,
  l2ERC20Predicate: POLYGON_ERC20_PREDICATE,
  l2FxTunnel: FX_CHILD,
  create2Deployer: CREATE2DEPLOYER,
  defender: DEFENDER,
  l1worm: ETH_WORMHOLE,
  l2worm: POLYGON_WORMHOLE,
};

export { config };
