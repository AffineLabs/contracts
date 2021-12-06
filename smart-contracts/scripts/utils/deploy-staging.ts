import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { ContractRegistryContracts } from "./deploy-contract-registry";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { assert } from "chai";
import create2deployerABI from "./assets/create2deployer.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { address } from "../../utils/types";

export interface StagingContracts {
  L1StagingContract: Contract,
  L2StagingContract: Contract,
}

export async function deployStagings(
  ethNetworkName: string,
  polygonNetworkName: string,
  contractRegistryContracts: ContractRegistryContracts,
  create2deployer: address,
): Promise<StagingContracts> {
  const salt = ethers.utils.formatBytes32String((new Date()).toISOString())

  hre.changeNetwork(ethNetworkName);
  const ethChainId = hre.network.config.chainId
  console.log('Ethereum chain ID:', ethChainId);

  hre.changeNetwork(polygonNetworkName);
  const polygonChainId = hre.network.config.chainId
  console.log('Polygon chain ID:', polygonChainId);

  // Network is not important.
  const creationCode = (await ethers.getContractFactory("Staging")).bytecode;
  const encodedParams = ethers.utils.defaultAbiCoder.encode([
    'address', 'address', 'uint24', 'uint24'
  ], [
    contractRegistryContracts.L1ContractRegistry.address,
    contractRegistryContracts.L2ContractRegistry.address,
    ethChainId,
    polygonChainId,
  ]).slice(2);
  const bytecode = `${creationCode}${encodedParams}`;

  hre.changeNetwork(ethNetworkName);
  let governance: SignerWithAddress = (await ethers.getSigners())[0];
  const l1Create2Deployer: Contract = new ethers.Contract(create2deployer, create2deployerABI, governance);
  await l1Create2Deployer.deploy(0, salt, bytecode);
  const l1StagingAddress: address = await l1Create2Deployer.computeAddress(salt, ethers.utils.keccak256(bytecode));
  const l1Staging: Contract = (await ethers.getContractFactory("Staging")).attach(l1StagingAddress);
  logContractDeploymentInfo(ethNetworkName, 'L1Staging', l1Staging);

  hre.changeNetwork(polygonNetworkName);
  governance = (await ethers.getSigners())[0];
  const l2Create2Deployer: Contract = new ethers.Contract(create2deployer, create2deployerABI, governance);
  await l2Create2Deployer.deploy(0, salt, bytecode);
  const l2StagingAddress: address = await l2Create2Deployer.computeAddress(salt, ethers.utils.keccak256(bytecode));
  const l2Staging: Contract = (await ethers.getContractFactory("Staging")).attach(l2StagingAddress);
  logContractDeploymentInfo(polygonNetworkName, 'L2Staging', l2Staging);

  assert(l1StagingAddress === l2StagingAddress, "L1 and L2 staging contract address must be same.")
  
  return {
    L1StagingContract: l1Staging,
    L2StagingContract: l2Staging,
  }
}