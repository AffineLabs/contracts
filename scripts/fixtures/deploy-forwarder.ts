import hre from "hardhat";
import { ethers } from "hardhat";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { getContractAddress } from "../../utils/export";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

async function deployForwarder(): Promise<any> {
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  const forwarderFactory = await ethers.getContractFactory("Forwarder");
  const forwarder = await forwarderFactory.deploy();
  await forwarder.deployed();

  console.log("polygon forwarder at: ", await getContractAddress(forwarder));
}

deployForwarder()
  .then(() => {
    console.log("Deployment finished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
