import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { ContractRegistryContracts } from "./deploy-contract-registry";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { assert } from "chai";
import { address } from "@maticnetwork/maticjs/dist/ts/types/Common";

export interface StagingContracts {
  L1StagingContract: Contract,
  L2StagingContract: Contract,
}

export async function deployStagings(
  ethNetworkName: string,
  polygonNetworkName: string,
  contractRegistryContracts: ContractRegistryContracts,
): Promise<StagingContracts> {

  hre.changeNetwork(ethNetworkName);
  const ethChainId = hre.network.config.chainId
  console.log('Ethereum chain ID:', ethChainId);

  hre.changeNetwork(polygonNetworkName);
  const polygonChainId = hre.network.config.chainId
  console.log('Polygon chain ID:', polygonChainId);

  const salt = ethers.utils.formatBytes32String((new Date()).toISOString())

  hre.changeNetwork(ethNetworkName);
  const l1StagingDeployerFactory: ContractFactory = await ethers.getContractFactory("StagingDeployer");
  const l1StagingDeployer: Contract = await l1StagingDeployerFactory.deploy(
    contractRegistryContracts.L1ContractRegistry.address,
    contractRegistryContracts.L2ContractRegistry.address,
    ethChainId,
    polygonChainId,
    salt,
  );
  await l1StagingDeployer.deployed();
  logContractDeploymentInfo(ethNetworkName, "L1StagingDeployer", l1StagingDeployer);
  const l1StagingFactory: ContractFactory = await ethers.getContractFactory("Staging");
  const l1StagingAddress: address = await l1StagingDeployer.getDeployedAddress();
  console.log('L1Staging address:', l1StagingAddress);


  hre.changeNetwork(polygonNetworkName);
  const l2StagingDeployerFactory: ContractFactory = await ethers.getContractFactory("StagingDeployer");
  const l2StagingDeployer: Contract = await l2StagingDeployerFactory.deploy(
    contractRegistryContracts.L1ContractRegistry.address,
    contractRegistryContracts.L2ContractRegistry.address,
    ethChainId,
    polygonChainId,
    salt,
  );
  await l2StagingDeployer.deployed();
  logContractDeploymentInfo(polygonNetworkName, "L2StagingDeployer", l2StagingDeployer);
  const l2StagingFactory: ContractFactory = await ethers.getContractFactory("Staging");
  const l2StagingAddress: address = await l2StagingDeployer.getDeployedAddress();
  console.log('L2Staging address:', l2StagingAddress);

  // assert(l1StagingAddress === l2StagingAddress, "L1 and L2 staging contract address must be same.")

  return {
    L1StagingContract: l1StagingFactory.attach(l1StagingAddress),
    L2StagingContract: l2StagingFactory.attach(l2StagingAddress),
  }
}