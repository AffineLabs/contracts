import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";
import { ethers, upgrades } from "hardhat";
import { Forwarder, TwoAssetBasket } from "../../typechain";
import { totalConfig } from "../utils/config";
import { POLYGON_MUMBAI } from "../utils/constants/blockchain";

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
      [
        "0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0",
        "0x007A22900a3B98143368Bd5906f8E17e9867581b",
        "0x0715A7794a1dc8e42615F059dD6e406A6594651A",
      ], // btc/eth price feeds
    ],
    { kind: "uups" },
  )) as TwoAssetBasket;
  console.log("basket at: ", basket.address);
  await basket.deployed();
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "PolygonBtcEthVault", "TwoAssetBasket", basket);
  return basket;
}
