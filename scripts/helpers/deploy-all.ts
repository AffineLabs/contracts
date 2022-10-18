import { deployVaults, VaultContracts } from "./deploy-vaults";
import { totalConfig } from "../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { deployBasket } from "./deploy-btc-eth";
import { address } from "../utils/types";
import { TwoAssetBasket } from "../../typechain";
import hre from "hardhat";
import { addToAddressBookAndDefender } from "../utils/export";
import { deployWormholeRouters, WormholeRouterContracts } from "./deploy-wormhole-router";
import { deployRouter } from "./deploy-router";
import { Forwarder, Router } from "typechain/src/polygon";
import { deployForwarder } from "./deploy-forwarder";

export interface AllContracts {
  forwarder: Forwarder;
  wormholeRouters: WormholeRouterContracts;
  vaults: VaultContracts;
  strategies: StrategyContracts | undefined;
  basket: TwoAssetBasket;
  router: Router;
}

export async function deployAll(
  ethNetworkName: string,
  polygonNetworkName: string,
  config: totalConfig,
): Promise<AllContracts> {
  const forwarder = await deployForwarder(polygonNetworkName);
  const router = await deployRouter(polygonNetworkName, forwarder);

  const vaults = await deployVaults(ethNetworkName, polygonNetworkName, config, forwarder);

  const wormholeRouters = await deployWormholeRouters(config, vaults, ethNetworkName, polygonNetworkName);

  const strategies = config.mainnet
    ? await deployStrategies(ethNetworkName, polygonNetworkName, vaults, config)
    : undefined;

  hre.changeNetwork(polygonNetworkName);
  const basket = await deployBasket(config, forwarder);

  // Add usdc to address book
  await addToAddressBookAndDefender(
    polygonNetworkName,
    "PolygonUSDC",
    config.mainnet ? "IERC20" : "MintableToken",
    config.l2.usdc,
    [],
    false,
  );
  await addToAddressBookAndDefender(polygonNetworkName, "Forwarder", "Forwarder", forwarder.address, [], false);

  return {
    wormholeRouters,
    forwarder,
    vaults,
    strategies,
    basket,
    router,
  };
}
