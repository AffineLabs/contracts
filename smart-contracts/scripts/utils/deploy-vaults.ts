import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { address } from "@maticnetwork/maticjs/dist/ts/types/Common";
import { ContractRegistryContracts } from "./deploy-contract-registry";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";

export interface VaultContracts {
  L1VaultContract: Contract,
  L2VaultContract: Contract,
}

export async function deployVaults(
  ethNetworkName: string, 
  ethUSDCAddress: address,
  polygonNetworkName: string,
  polygonUSDCAddress: address,
  governance: SignerWithAddress,
  contractRegistryContracts: ContractRegistryContracts,
): Promise<VaultContracts> {
  // Deploy vault in eth.
  hre.changeNetwork(ethNetworkName);
  const l1VaultFactory: ContractFactory = await ethers.getContractFactory("L1Vault");
  const l1Vault: Contract = await l1VaultFactory.deploy(governance.address, ethUSDCAddress, contractRegistryContracts.L1ContractRegistry.address);
  await l1Vault.deployed();
  logContractDeploymentInfo(ethNetworkName, "L1Vault", l1Vault);

  // Deploy vault in polygon.
  hre.changeNetwork(polygonNetworkName);
  const l2VaultFactory: ContractFactory = await ethers.getContractFactory("L2Vault");
  const l2Vault: Contract = await l2VaultFactory.deploy(governance.address, polygonUSDCAddress, 9, 1, contractRegistryContracts.L2ContractRegistry.address);
  await l2Vault.deployed();
  logContractDeploymentInfo(polygonNetworkName, "L2Vault", l2Vault);

  return {
    L1VaultContract: l1Vault,
    L2VaultContract: l2Vault,
  }
}