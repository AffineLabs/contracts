import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import scriptUtils from "./utils";

dotenvConfig({ path: resolve(__dirname, "./.env") });

async function deployAAVE(): Promise<any> {
  const [deployer] = await ethers.getSigners();

  const l2VaultFactory = await scriptUtils.getContractFactory("L2Vault", deployer);
  // Hardcoding kovan values, TODO: remove
  const l2Vault = await l2VaultFactory.deploy(
    deployer.address,
    "0xe22da380ee6b445bb8273c81944adeb6e8450422",
    9,
    1,
    deployer.address,
  );
  await l2Vault.deployed();
  console.log("vault done");

  // A fake incentives controller, no real one exists on kovan
  const dummyFactory = await scriptUtils.getContractFactory("DummyIncentivesController", deployer);
  const dummyIncentives = await dummyFactory.deploy();
  await dummyIncentives.deployed();
  console.log("incentives done");

  const stratFactory = await scriptUtils.getContractFactory("L2AAVEStrategy", deployer);

  const strategy = await stratFactory.deploy(
    l2Vault.address,
    "0x1E40B561EC587036f9789aF83236f057D1ed2A90", // aave adress provider registry
    dummyIncentives.address,
    "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff", // quickswap -> these are polygon addresses that won't be used
    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // wrapped matic -> as above
    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
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
