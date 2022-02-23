import { deployVaults, VaultContracts } from "./deploy-vaults";
import { Config } from "../../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { address } from "../../utils/types";

export interface AllContracts {
  vaults: VaultContracts;
  strategies: StrategyContracts;
}

export async function deployAll(
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const vaults = await deployVaults(
    l1Governance,
    l2Governance,
    ethNetworkName,
    polygonNetworkName,
    config,
  );
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
