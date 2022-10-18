import hre from "hardhat";
import { ethers } from "hardhat";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { Forwarder } from "typechain";

dotenvConfig({ path: resolve(__dirname, "./.env") });

export async function deployForwarder(polygonNetworkName: string): Promise<Forwarder> {
  hre.changeNetwork(polygonNetworkName);
  const forwarderFactory = await ethers.getContractFactory("Forwarder");
  const forwarder = await forwarderFactory.deploy();
  await forwarder.deployed();

  console.log("polygon forwarder at: ", forwarder.address);
  return forwarder;
}
