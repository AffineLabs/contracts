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
  const vaults = await deployVaults(config.l1Governance, config.l2Governance, ethNetworkName, polygonNetworkName, config);
  const strategies = await deployStrategies(ethNetworkName, polygonNetworkName, vaults, config);

  console.log("Adding strategies to vault...");
  // add L2 strategies
  const decimals = await vaults.l2Vault.decimals();
  vaults.l2Vault.addStrategy(strategies.l2.aave.address, 10_000, 0, ethers.utils.parseUnits("10000", decimals));

  // add L1 strategies
  vaults.l1Vault.addStrategy(strategies.l1.compound.address, 10_000, 0, ethers.utils.parseUnits("10000", decimals));
  console.log("Strategies added");

  return {
    vaults,
    strategies,
  };
}
