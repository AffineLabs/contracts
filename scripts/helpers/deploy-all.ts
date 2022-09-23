import { deployVaults, VaultContracts } from "./deploy-vaults";
import { totalConfig } from "../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { deployBasket } from "./deploy-btc-eth";
import { address } from "../utils/types";
import { TwoAssetBasket } from "../../typechain";
import hre from "hardhat";
import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";
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
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: totalConfig,
): Promise<AllContracts> {
  const forwarder = await deployForwarder(polygonNetworkName);
  const router = await deployRouter(polygonNetworkName, forwarder);
  const wormholeRouters = await deployWormholeRouters(config, ethNetworkName, polygonNetworkName);
  const vaults = await deployVaults(
    l1Governance,
    l2Governance,
    ethNetworkName,
    polygonNetworkName,
    config,
    wormholeRouters,
    forwarder,
  );
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
  await addToAddressBookAndDefender(
    polygonNetworkName,
    "Forwarder",
    "Forwarder",
    await getContractAddress(forwarder),
    [],
    false,
  );

  return {
    wormholeRouters,
    forwarder,
    vaults,
    strategies,
    basket,
    router,
  };
}
