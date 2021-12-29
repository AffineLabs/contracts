import { deployVaults, VaultContracts } from "./deploy-vaults";
import { address } from "../../utils/types";
import { Config } from "../../utils/config";

export interface AllContracts {
  vaultContracts: VaultContracts;
}

export async function deployAll(
  governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const vaultContracts: VaultContracts = await deployVaults(governance, ethNetworkName, polygonNetworkName, config);

  return {
    vaultContracts,
  };
}
