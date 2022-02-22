import { ethers } from "hardhat";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { config } from "../utils/config";

dotenvConfig({ path: resolve(__dirname, "./.env") });

// This only works on mumbai for now
async function deployBasket(): Promise<any> {
  const [deployer] = await ethers.getSigners();

  const BasketFactory = await ethers.getContractFactory("TwoAssetBasket");
  const basket = await BasketFactory.deploy(
    deployer.address,
    "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // sushiswap router
    config.l2USDC,
    [config.wbtc, config.weth],
    [100, 100],
    ["0x007A22900a3B98143368Bd5906f8E17e9867581b", "0x0715A7794a1dc8e42615F059dD6e406A6594651A"], // btc/eth price feeds
  );
  console.log("basket at: ", basket.address);
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
