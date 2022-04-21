import { ethers } from "hardhat";
import { TwoAssetBasket } from "../../typechain";
import { Config } from "../utils/config";
import { POLYGON_MUMBAI } from "../utils/constants/blockchain";
import { addToAddressBookAndDefender } from "../utils/export";
// This only works on mumbai for now
export async function deployBasket(config: Config): Promise<TwoAssetBasket> {
  const [deployer] = await ethers.getSigners();

  const BasketFactory = await ethers.getContractFactory("TwoAssetBasket");
  const basket = await BasketFactory.deploy(
    deployer.address,
    config.forwarder,
    ethers.BigNumber.from(10).pow(8).mul(50_000), // $50,000 dollar rebalance delta (8 decimals to work with chainlink)
    ethers.BigNumber.from(10).pow(8).mul(10_000), // $10_000 block size
    "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // sushiswap router
    config.l2USDC,
    [config.wbtc, config.weth],
    [100, 100],
    ["0x007A22900a3B98143368Bd5906f8E17e9867581b", "0x0715A7794a1dc8e42615F059dD6e406A6594651A"], // btc/eth price feeds
  );
  console.log("basket at: ", basket.address);
  await basket.deployed();
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "PolygonBtcEthVault", "TwoAssetBasket", basket);
  return basket;
}