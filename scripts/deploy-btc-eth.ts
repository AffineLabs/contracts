import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { config } from "../utils/config";

import { BasketVault } from "../typechain/BasketVault";

import scriptUtils from "./utils";

dotenvConfig({ path: resolve(__dirname, "./.env") });

// This only works on mumbai for now
async function deployBasket(): Promise<any> {
  const [deployer] = await ethers.getSigners();

  const BasketFactory = await scriptUtils.getContractFactory("BasketVault");
  const basket = (await BasketFactory.deploy(
    deployer.address,
    "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // sushiswap router
    config.l2USDC,
    ["btc", "eth"],
    [100, 100],
    ["0x007A22900a3B98143368Bd5906f8E17e9867581b", "0x0715A7794a1dc8e42615F059dD6e406A6594651A"],
  )) as BasketVault;
}

deployBasket()
  .then(() => {
    console.log("Dummy deployment finished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
