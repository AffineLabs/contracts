import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";

dotenvConfig({ path: resolve(__dirname, "./.env") });

async function deployDummy(): Promise<any> {
  const [deployer] = await ethers.getSigners();

  const DummyFactory = await ethers.getContractFactory("DummyVault", deployer);
  const prices = {
    1: ["Alpine Save", "alpSave"],
    2: ["Alpine Balanced", "alpBal"],
    3: ["Alpine Aggresive", "alpAggr"],
  };
  for (const [price, [name, symbol]] of Object.entries(prices)) {
    const vault = await DummyFactory.deploy(name, symbol, price);
    await vault.deployed();
    console.log(`vault at ${vault.address} deployed`);
  }
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
