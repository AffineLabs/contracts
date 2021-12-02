import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { ContractRegistryContracts } from "./deploy-contract-registry";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";

export interface StagingContracts {
  L2StagingContract: Contract,
}

export async function deployStagings(
  polygonNetworkName: string,
  contractRegistryContracts: ContractRegistryContracts,
): Promise<StagingContracts> {
  // Deploy vault in polygon.
  hre.changeNetwork(polygonNetworkName);
  const l2StagingFactory: ContractFactory = await ethers.getContractFactory("L2Staging");
  const l2Staging: Contract = await l2StagingFactory.deploy(contractRegistryContracts.L2ContractRegistry.address);
  await l2Staging.deployed();
  logContractDeploymentInfo(polygonNetworkName, "L2Staging", l2Staging);

  return {
    L2StagingContract: l2Staging,
  }
}