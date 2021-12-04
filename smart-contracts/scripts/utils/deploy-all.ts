import { ContractRegistryContracts, deployContractRegistry } from "./deploy-contract-registry";
import { deployFxBridge, FxTunnelContracts } from "./deploy-fx-bridge";
import { deployVaults, VaultContracts } from "./deploy-vaults";
import hre from "hardhat";
import { deployStagings, StagingContracts } from "./deploy-staging";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { address } from "../../utils/types";

export interface AllContracts {
  contractRegistryContracts: ContractRegistryContracts,
  fxTunnelContracts: FxTunnelContracts,
  vaultContracts: VaultContracts,
  stagingContract: StagingContracts,
}

export async function deployAll(
    governance: SignerWithAddress,
    defender: SignerWithAddress,
    ethNetworkName: string,
    polygonNetworkName: string,
    l1CheckpointManager: address,
    l1ChainManager: address,
    l1USDC: address,
    l1FxTunnel: address,
    l2USDC: address,
    l2ERC20Predicate: address,
    l2FxTunnel: address,
    create2deployer: address,
): Promise<AllContracts> {
  const contractRegistryContracts: ContractRegistryContracts = await deployContractRegistry(
    ethNetworkName, 
    polygonNetworkName,
  )
  const fxTunnelContracts: FxTunnelContracts = await deployFxBridge(
    ethNetworkName, 
    polygonNetworkName, 
    l1CheckpointManager, 
    l1FxTunnel, 
    l2FxTunnel, 
    contractRegistryContracts
  )
  const vaultContracts: VaultContracts = await deployVaults(
    ethNetworkName, 
    l1USDC, 
    polygonNetworkName,
    l2USDC,
    governance,
    contractRegistryContracts)
  const stagingContract: StagingContracts = await deployStagings(
    ethNetworkName,
    polygonNetworkName,
    contractRegistryContracts,
    create2deployer,
  );

  // Initialize Eth contract registry.
  hre.changeNetwork(ethNetworkName);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("L1FxTunnel", fxTunnelContracts.L1FxTunnel.address);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("L1Vault", vaultContracts.L1VaultContract.address);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("L1USDC", l1USDC);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("L1Staging", stagingContract.L1StagingContract.address);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("L2Staging", stagingContract.L2StagingContract.address);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("L2ERC20Predicate", l2ERC20Predicate);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("L1ChainManager", l1ChainManager);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("Defender", defender.address);
  await contractRegistryContracts.L1ContractRegistry.addOrUpdateAddress("Governance", governance.address);

  // Initialize polygon contract registry.
  hre.changeNetwork(polygonNetworkName);
  await contractRegistryContracts.L2ContractRegistry.addOrUpdateAddress("L2FxTunnel", fxTunnelContracts.L2FxTunnel.address);
  await contractRegistryContracts.L2ContractRegistry.addOrUpdateAddress("L2Vault", vaultContracts.L2VaultContract.address);
  await contractRegistryContracts.L2ContractRegistry.addOrUpdateAddress("L1Staging", stagingContract.L1StagingContract.address);
  await contractRegistryContracts.L2ContractRegistry.addOrUpdateAddress("L2Staging", stagingContract.L2StagingContract.address)
  await contractRegistryContracts.L2ContractRegistry.addOrUpdateAddress("L2USDC", l2USDC);
  await contractRegistryContracts.L2ContractRegistry.addOrUpdateAddress("Defender", defender.address);
  await contractRegistryContracts.L2ContractRegistry.addOrUpdateAddress("Governance", governance.address);

  console.log('Initialization done.\n')

  return {
    contractRegistryContracts,
    fxTunnelContracts,
    vaultContracts,
    stagingContract,
  }
}