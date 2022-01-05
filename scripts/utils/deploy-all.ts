import { deployVaults, VaultContracts } from "./deploy-vaults";
import { address } from "../../utils/types";
import { Config } from "../../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";

export interface AllContracts {
  vaultContracts: VaultContracts;
  strategies: StrategyContracts;
}

export async function deployAll(
  governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const vaultContracts: VaultContracts = await deployVaults(governance, ethNetworkName, polygonNetworkName, config);
  const strategies = await deployStrategies(governance, ethNetworkName, polygonNetworkName, config);

  // TODO: Add strategies to Vault
  return {
    vaultContracts,
    strategies,
  };
}
