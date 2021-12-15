import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";

import scriptUtils from "./utils";

dotenvConfig({ path: resolve(__dirname, "./.env") });

async function deployDummy(): Promise<any> {
  const [deployer] = await ethers.getSigners();
  const DummyFactory = await scriptUtils.getContractFactory("DummyVault");

  console.log("factory fectched: ");
  const vault = await DummyFactory.deploy();
  console.log("vault address: ", vault.address);
  await vault.deployed();
}

deployDummy()
  .then(() => {
    console.log("Dummy deployment finished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
