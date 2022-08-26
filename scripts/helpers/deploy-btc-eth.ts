import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";
import { ethers, upgrades } from "hardhat";
import { Forwarder, TwoAssetBasket } from "../../typechain";
import { totalConfig } from "../utils/config";

export async function deployBasket(config: totalConfig, forwarder: Forwarder): Promise<TwoAssetBasket> {
  const BasketFactory = await ethers.getContractFactory("TwoAssetBasket");
  const basket = (await upgrades.deployProxy(
    BasketFactory,
    [
      config.l2.governance,
      await getContractAddress(forwarder),
      config.l2.aave.uniRouter,
      config.l2.usdc,
      [config.l2.wbtc, config.l2.weth],
      [100, 100],
      [config.l2.feeds.usdc, config.l2.feeds.wbtc, config.l2.feeds.weth],
    ],
    { kind: "uups" },
  )) as TwoAssetBasket;
  console.log("basket at: ", basket.address);
  await basket.deployed();
  await addToAddressBookAndDefender(
    process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    "PolygonBtcEthVault",
    "TwoAssetBasket",
    basket,
  );
  return basket;
}
