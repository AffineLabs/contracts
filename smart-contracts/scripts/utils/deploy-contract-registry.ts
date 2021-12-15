import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import scriptUtils from "../utils";

export interface ContractRegistryContracts {
  L1ContractRegistry: Contract;
  L2ContractRegistry: Contract;
}

export async function deployContractRegistry(
  ethNetworkName: string,
  polygonNetworkName: string,
): Promise<ContractRegistryContracts> {
  // Deploy contract registry eth.
  hre.changeNetwork(ethNetworkName);
  const L1ContractRegistryFactory: ContractFactory = await scriptUtils.getContractFactory("ContractRegistry");
  const l1ContractRegistry: Contract = await L1ContractRegistryFactory.deploy();
  await l1ContractRegistry.deployed();
  logContractDeploymentInfo(ethNetworkName, "L1ContractRegistry", l1ContractRegistry);

  // Deploy contract registry polygon.
  hre.changeNetwork(polygonNetworkName);
  const L2ContractRegistryFactory: ContractFactory = await scriptUtils.getContractFactory("ContractRegistry");
  const l2ContractRegistry: Contract = await L2ContractRegistryFactory.deploy();
  await l2ContractRegistry.deployed();
  logContractDeploymentInfo(polygonNetworkName, "L2ContractRegistry", l2ContractRegistry);

  return {
    L1ContractRegistry: l1ContractRegistry,
    L2ContractRegistry: l2ContractRegistry,
  };
}
