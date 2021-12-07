import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { ContractRegistryContracts } from "./deploy-contract-registry";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { address } from "../../utils/types";

export interface VaultContracts {
  L1VaultContract: Contract,
  L2VaultContract: Contract,
}

export async function deployVaults(
  ethNetworkName: string, 
  ethUSDCAddress: address,
  polygonNetworkName: string,
  polygonUSDCAddress: address,
  governance: address,
  contractRegistryContracts: ContractRegistryContracts,
): Promise<VaultContracts> {
  // Deploy vault in eth.
  hre.changeNetwork(ethNetworkName);
  const l1VaultFactory: ContractFactory = await ethers.getContractFactory("L1Vault");
  const l1Vault: Contract = await l1VaultFactory.deploy(governance, ethUSDCAddress, contractRegistryContracts.L1ContractRegistry.address);
  await l1Vault.deployed();
  logContractDeploymentInfo(ethNetworkName, "L1Vault", l1Vault);

  // Deploy vault in polygon.
  hre.changeNetwork(polygonNetworkName);
  const l2VaultFactory: ContractFactory = await ethers.getContractFactory("L2Vault");
  const l2Vault: Contract = await l2VaultFactory.deploy(governance, polygonUSDCAddress, 9, 1, contractRegistryContracts.L2ContractRegistry.address);
  await l2Vault.deployed();
  logContractDeploymentInfo(polygonNetworkName, "L2Vault", l2Vault);

  return {
    L1VaultContract: l1Vault,
    L2VaultContract: l2Vault,
  }
}