import { ethers } from "hardhat";
import { config } from "../utils/config";
import { AllContracts, deployAll } from "./utils/deploy-all";

const ETH_NETWORK_NAME = "ethGoerli";
const POLYGON_NETWORK_NAME = "polygonMumbai";

async function deployAllGoerliMumbai(): Promise<AllContracts> {
  return deployAll(config.l1Governance, config.l2Governance, ETH_NETWORK_NAME, POLYGON_NETWORK_NAME, config);
}

deployAllGoerliMumbai()
  .then(() => {
    console.log("All Contracts deployed and initialized!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
