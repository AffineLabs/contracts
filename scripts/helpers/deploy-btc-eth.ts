import { ethers, upgrades } from "hardhat";
import { TwoAssetBasket } from "../../typechain";
import { Config } from "../utils/config";
import { POLYGON_MUMBAI } from "../utils/constants/blockchain";
import { addToAddressBookAndDefender } from "../utils/export";
// This only works on mumbai for now
export async function deployBasket(config: Config): Promise<TwoAssetBasket> {
  const BasketFactory = await ethers.getContractFactory("TwoAssetBasket");
  const basket = (await upgrades.deployProxy(
    BasketFactory,
    [
      config.l2Governance,
      config.forwarder,
      "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // sushiswap router
      config.l2USDC,
      [config.wbtc, config.weth],
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
