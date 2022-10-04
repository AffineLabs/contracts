import hre from "hardhat";
import { ethers } from "hardhat";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

async function deployCreate3(): Promise<any> {
  hre.changeNetwork(ETH_NETWORK_NAME);

  const [deployer] = await ethers.getSigners();
  console.log("deployer: ", deployer.address);
  //   let create3Factory = await ethers.getContractFactory("Create3Deployer");
  //   let create3 = await create3Factory.deploy();
  //   await create3.deployed();
  //   console.log("eth create3: ", create3.address);

  hre.changeNetwork(POLYGON_NETWORK_NAME);

  const create3Factory = await ethers.getContractFactory("Create3Deployer");
  const create3 = await create3Factory.deploy();
  await create3.deployed();
  console.log("polygon create3: ", create3.address);
}

deployCreate3()
  .then(() => {
    console.log("Create2 deployment finsished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
