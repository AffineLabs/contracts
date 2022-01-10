import { deployVaults, VaultContracts } from "./deploy-vaults";
import { address } from "../../utils/types";
import { Config } from "../../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { ethers } from "ethers";

export interface AllContracts {
  vaults: VaultContracts;
  strategies: StrategyContracts;
}

export async function deployAll(
  governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const vaults = await deployVaults(governance, ethNetworkName, polygonNetworkName, config);
  const strategies = await deployStrategies(governance, ethNetworkName, polygonNetworkName, vaults, config);

  console.log("Adding strategies to vault...");
  // add L2 strategies
  const l2Decimals = await vaults.l2Vault.decimals();
  vaults.l2Vault.addStrategy(strategies.l2.aave.address, 10_000, 0, ethers.utils.parseUnits("10000", l2Decimals));

  // add L1 strategies
  const l1Decimals = await vaults.l1Vault.decimals();
  vaults.l1Vault.addStrategy(strategies.l1.compound.address, 10_000, 0, ethers.utils.parseUnits("10000", l1Decimals));
  console.log("Strategies added");

  return {
    vaults,
    strategies,
  };
}
