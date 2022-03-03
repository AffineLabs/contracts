import { deployVaults, VaultContracts } from "./deploy-vaults";
import { Config } from "../../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { deployBasket } from "./deploy-btc-eth";
import { address } from "../../utils/types";
import { TwoAssetBasket } from "../../typechain";
import { ethers, changeNetwork } from "hardhat";

export interface AllContracts {
  vaults: VaultContracts;
  strategies: StrategyContracts;
  basket: TwoAssetBasket;
}

export async function deployAll(
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const vaults = await deployVaults(l1Governance, l2Governance, ethNetworkName, polygonNetworkName, config);
  const strategies = await deployStrategies(ethNetworkName, polygonNetworkName, vaults);

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

  changeNetwork(polygonNetworkName);
  const basket = await deployBasket(config);

  return {
    vaults,
    strategies,
    basket,
  };
}
