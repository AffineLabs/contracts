// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from 'hardhat';
import { Contract, ContractFactory } from 'ethers';
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { assert } from 'console';
dotenvConfig({ path: resolve(__dirname, "./.env") });

const CHECKPOINT_MANAGER = process.env.CHECKPOINT_MANAGER || "";
const FX_ROOT = process.env.FX_ROOT || "";

assert(CHECKPOINT_MANAGER !== "", "Checkpint Manager address must not be empty. Please set CHECKPOINT_MANAGER in the .env file.");
assert(FX_ROOT !== "", "Fx root address must not be empty. Please set FX_ROOT in the .env file.");

async function main(): Promise<void> {
  // Hardhat always runs the compile task when running scripts through it.
  // If this runs in a standalone fashion you may want to call compile manually
  // to make sure everything is compiled
  // await run("compile");
  // We get the contract to deploy
  const FxStateRootTunnelFactory: ContractFactory = await ethers.getContractFactory(
    'FxStateRootTunnel',
  );
  const fxStateRootTunnel: Contract = await FxStateRootTunnelFactory.deploy(CHECKPOINT_MANAGER, FX_ROOT);
  await fxStateRootTunnel.deployed();
  console.log('FxStateRootTunnel deployed to: ', fxStateRootTunnel.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
