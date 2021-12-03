import { ethers } from "hardhat";
import { Contract, ContractFactory, Wallet } from "ethers";
import { ContractRegistryContracts } from "./deploy-contract-registry";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { assert } from "chai";
import { address } from "@maticnetwork/maticjs/dist/ts/types/Common";
import create2deployerABI from "./assets/create2deployer.json";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

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
  const stagingFactory: ContractFactory = await ethers.getContractFactory("Staging");

  hre.changeNetwork(ethNetworkName);
  const ethChainId = hre.network.config.chainId
  console.log('Ethereum chain ID:', ethChainId);

  hre.changeNetwork(polygonNetworkName);
  const polygonChainId = hre.network.config.chainId
  console.log('Polygon chain ID:', polygonChainId);

  const bytecode = stagingFactory.interface.encodeDeploy([
    contractRegistryContracts.L1ContractRegistry.address,
    contractRegistryContracts.L2ContractRegistry.address,
    ethChainId,
    polygonChainId,
  ])

  hre.changeNetwork(ethNetworkName);
  let governance: SignerWithAddress = (await ethers.getSigners())[0];
  const l1Create2Deployer: Contract = new ethers.Contract(create2deployer, create2deployerABI, governance);
  await l1Create2Deployer.deploy(0, salt, bytecode)
  const l1StagingAddress: address = await l1Create2Deployer.computeAddress(salt, ethers.utils.keccak256(bytecode));

  hre.changeNetwork(polygonNetworkName);
  governance = (await ethers.getSigners())[0];
  const l2Create2Deployer: Contract = new ethers.Contract(create2deployer, create2deployerABI, governance);
  await l2Create2Deployer.deploy(0, salt, bytecode)
  const l2StagingAddress: address = await l2Create2Deployer.computeAddress(salt, ethers.utils.keccak256(bytecode));

  assert(l1StagingAddress === l2StagingAddress, "L1 and L2 staging contract address must be same.")

  const l1StagingFactory: Contract = (await ethers.getContractFactory("Staging")).attach(l1StagingAddress);
  const l2StagingFactory: Contract = (await ethers.getContractFactory("Staging")).attach(l2StagingAddress);
  
  logContractDeploymentInfo(ethNetworkName, 'L1Staging', l1StagingFactory);
  logContractDeploymentInfo(polygonNetworkName, 'L2Staging', l2StagingFactory);
  
  return {
    L1StagingContract: l1StagingFactory,
    L2StagingContract: l2StagingFactory,
  }
}