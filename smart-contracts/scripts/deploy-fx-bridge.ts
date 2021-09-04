// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from 'hardhat';
import { Contract, ContractFactory } from 'ethers';
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { assert } from 'console';
import hre from "hardhat";
import {getEthGoerliExplorerLink, getPolygonMumbaiExplorerLink} from '../utils/bc-explorer-links'

dotenvConfig({ path: resolve(__dirname, "./.env") });

const CHECKPOINT_MANAGER = process.env.CHECKPOINT_MANAGER || "";
const FX_ROOT = process.env.FX_ROOT || "";
const FX_CHILD = process.env.FX_CHILD || "";

assert(CHECKPOINT_MANAGER !== "", "Checkpint Manager address must not be empty. Please set CHECKPOINT_MANAGER in the .env file.");
assert(FX_ROOT !== "", "Fx root address must not be empty. Please set FX_ROOT in the .env file.");
assert(FX_CHILD !== "", "Fx child address must not be empty. Please set FX_CHILD in the .env file.");


async function main(): Promise<void> {
  // Deploy root tunnel in eth goerli.
  hre.changeNetwork('ethGoerli');
  const FxStateRootTunnelFactory: ContractFactory = await ethers.getContractFactory(
    'FxStateRootTunnel',
  );
  const fxStateRootTunnel: Contract = await FxStateRootTunnelFactory.deploy(CHECKPOINT_MANAGER, FX_ROOT);
  const fxStateRootTunnelDeployTxRcpt = await fxStateRootTunnel.deployed();
  console.log('FxStateRootTunnel deployed to:', fxStateRootTunnel.address, 'tx:', getEthGoerliExplorerLink(fxStateRootTunnelDeployTxRcpt.deployTransaction.hash));

  // Deploy child tunnel in polygon mumbai testnet.
  hre.changeNetwork('polygonMumbai');
  const FxStateChildTunnelFactory: ContractFactory = await ethers.getContractFactory(
    'FxStateChildTunnel',
  );
  const fxStateChildTunnel: Contract = await FxStateChildTunnelFactory.deploy(FX_CHILD);
  const fxStateChildTunnelDeployTxRcpt = await fxStateChildTunnel.deployed();
  console.log('FxStateChildTunnel deployed to:', fxStateChildTunnel.address, 'tx:', getPolygonMumbaiExplorerLink(fxStateChildTunnelDeployTxRcpt.deployTransaction.hash));

  hre.changeNetwork('ethGoerli');
  console.log('Setting fx child tunnel address in fx root.');
  const setFxChildAddressTx = await fxStateRootTunnel.setFxChildTunnel(fxStateChildTunnel.address)
  console.log('tx:', getEthGoerliExplorerLink(setFxChildAddressTx.hash));

  hre.changeNetwork('polygonMumbai');
  console.log('Setting fx root tunnel address in fx child.');
  const setFxRootAddressTx = await fxStateChildTunnel.setFxRootTunnel(fxStateRootTunnel.address)
  console.log('tx:', getPolygonMumbaiExplorerLink(setFxRootAddressTx.hash));

  console.log('Finished deploying tunnel successfully.')
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
