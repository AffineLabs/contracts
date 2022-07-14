import { deployVaults, VaultContracts } from "./deploy-vaults";
import { Config } from "../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { deployBasket } from "./deploy-btc-eth";
import { address } from "../utils/types";
import { MintableToken__factory, TwoAssetBasket } from "../../typechain";
import { ethers } from "hardhat";
import hre from "hardhat";
import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";
import { POLYGON_MUMBAI } from "../utils/constants/blockchain";
import { deployWormholeRouters, WormholeRouterContracts } from "./deploy-wormhole-router";
import { deployRouter } from "./deploy-router";
import { Router } from "typechain/src/polygon";

export interface AllContracts {
  wormholeRouters: WormholeRouterContracts;
  vaults: VaultContracts;
  strategies: StrategyContracts;
  basket: TwoAssetBasket;
  router: Router;
}

export async function deployAll(
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const wormholeRouters = await deployWormholeRouters(ethNetworkName, polygonNetworkName);
  const vaults = await deployVaults(
    l1Governance,
    l2Governance,
    ethNetworkName,
    polygonNetworkName,
    config,
    wormholeRouters,
  );
  const strategies = await deployStrategies(ethNetworkName, polygonNetworkName, vaults);
  const router = await deployRouter(polygonNetworkName);
  // TODO: Consider strategies. We can't add strategies anymore since the timelock address is the governance address
  // In tests we can simply use hardhat's mocking abilities.

  // console.log("Adding strategies to vault...");
  // add L2 strategies
  // changeNetwork(polygonNetworkName);
  // let [governanceSigner] = await ethers.getSigners();
  // await vaults.l2Vault.connect(governanceSigner).addStrategy(strategies.l2.aave.address);

  // add L1 strategies
  // changeNetwork(ethNetworkName);
  // [governanceSigner] = await ethers.getSigners();
  // await vaults.l1Vault.connect(governanceSigner).addStrategy(strategies.l1.compound.address);
  // console.log("Strategies added");
  hre.changeNetwork(polygonNetworkName);
  const basket = await deployBasket(config);

  // Add usdc to address book, TODO: handle the production version of this
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "PolygonUSDC", "MintableToken", config.l2USDC, [], false);
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "Forwarder", "Forwarder", config.forwarder, [], false);

  return {
    wormholeRouters,
    vaults,
    strategies,
    basket,
    router,
  };
}
