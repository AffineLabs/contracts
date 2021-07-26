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

const FX_CHILD = process.env.FX_CHILD || "";

assert(FX_CHILD !== "", "Fx child address must not be empty. Please set FX_CHILD in the .env file.");

async function main(): Promise<void> {
  // Hardhat always runs the compile task when running scripts through it.
  // If this runs in a standalone fashion you may want to call compile manually
  // to make sure everything is compiled
  // await run("compile");
  // We get the contract to deploy
  const FxStateChildTunnelFactory: ContractFactory = await ethers.getContractFactory(
    'FxStateChildTunnel',
  );
  const fxStateChildTunnel: Contract = await FxStateChildTunnelFactory.deploy(FX_CHILD);
  await fxStateChildTunnel.deployed();
  console.log('FxStateChildTunnel deployed to: ', fxStateChildTunnel.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
