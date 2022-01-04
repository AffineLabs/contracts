import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import scriptUtils from "./utils";
import { config } from "../utils/config";

dotenvConfig({ path: resolve(__dirname, "./.env") });

async function deployAAVE(): Promise<any> {
  let [deployer] = await ethers.getSigners();

  // Using address of USDC compatible with AAVE on mumbai
  const myConfig = { ...config };
  myConfig.l2USDC = "0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e";
  const vaultContracts = await scriptUtils.deployVaults(deployer.address, "ethGoerli", "polygonMumbai", myConfig);

  // A fake incentives controller, no real one exists on mumbai
  [deployer] = await ethers.getSigners();
  const dummyFactory = await scriptUtils.getContractFactory("DummyIncentivesController", deployer);
  const dummyIncentives = await dummyFactory.deploy();
  await dummyIncentives.deployed();
  console.log("incentives done");

  const stratFactory = await scriptUtils.getContractFactory("L2AAVEStrategy", deployer);

  // Hardcoding mumbai values
  const strategy = await stratFactory.deploy(
    vaultContracts.l2Vault.address,
    "0xE6ef11C967898F9525D550014FDEdCFAB63536B5", // aave adress provider registry
    dummyIncentives.address,
    "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff", // quickswap -> these are polygon mainnet addresses that won't be used
    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // reward token -> wrapped matic -> as above
    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // wrapped matic address
  );
  console.log("strategy address: ", strategy.address);
  await strategy.deployed();
}

deployAAVE()
  .then(() => {
    console.log("Strategy deployment finished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
