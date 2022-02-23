import { deployVaults, VaultContracts } from "./deploy-vaults";
import { Config } from "../../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { ethers } from "ethers";

export interface AllContracts {
  vaults: VaultContracts;
  strategies: StrategyContracts;
}

export async function deployAll(
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const vaults = await deployVaults(ethNetworkName, polygonNetworkName, config);
  const strategies = await deployStrategies(ethNetworkName, polygonNetworkName, vaults);

  console.log("Adding strategies to vault...");
  // add L2 strategies
  const decimals = await vaults.l2Vault.decimals();
  vaults.l2Vault.addStrategy(strategies.l2.aave.address);

  // add L1 strategies
  vaults.l1Vault.addStrategy(strategies.l1.compound.address);
  console.log("Strategies added");

  return {
    vaults,
    strategies,
  };
}
