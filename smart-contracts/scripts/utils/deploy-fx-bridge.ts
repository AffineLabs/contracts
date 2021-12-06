import { ethers } from 'hardhat';
import { Contract, ContractFactory, ContractTransaction } from 'ethers';
import hre from "hardhat";
import { logContractDeploymentInfo, getTxExplorerLink } from '../../utils/bc-explorer-links'
import { ContractRegistryContracts } from './deploy-contract-registry';
import { address } from "../../utils/types";

export interface FxTunnelContracts {
  L1FxTunnel: Contract,
  L2FxTunnel: Contract,
}

export async function deployFxBridge(
  ethNetworkName: string, 
  polygonNetworkName: string,
  checkpointManager: address,
  fxRootAddress: address,
  fxChildAddress: address,
  contractRegistryContracts: ContractRegistryContracts,
): Promise<FxTunnelContracts> {
  // Deploy root tunnel in eth.
  hre.changeNetwork(ethNetworkName);
  const FxStateRootTunnelFactory: ContractFactory = await ethers.getContractFactory('FxStateRootTunnel');
  const fxStateRootTunnel: Contract = await FxStateRootTunnelFactory.deploy(checkpointManager, fxRootAddress, contractRegistryContracts.L1ContractRegistry.address);
  await fxStateRootTunnel.deployed();
  logContractDeploymentInfo(ethNetworkName, "FxStateRootTunnel", fxStateRootTunnel);

  // Deploy child tunnel in polygon.
  hre.changeNetwork(polygonNetworkName);
  const FxStateChildTunnelFactory: ContractFactory = await ethers.getContractFactory('FxStateChildTunnel');
  const fxStateChildTunnel: Contract = await FxStateChildTunnelFactory.deploy(fxChildAddress, contractRegistryContracts.L2ContractRegistry.address);
  await fxStateChildTunnel.deployed();
  logContractDeploymentInfo(polygonNetworkName, "FxStateChildTunnel", fxStateChildTunnel);

  hre.changeNetwork(ethNetworkName);
  console.log('Setting fx child tunnel address in fx root.');
  const setFxChildAddressTx: ContractTransaction = await fxStateRootTunnel.setFxChildTunnel(fxStateChildTunnel.address)
  console.log(' > tx:', getTxExplorerLink(ethNetworkName, setFxChildAddressTx));

  hre.changeNetwork(polygonNetworkName);
  console.log('Setting fx root tunnel address in fx child.');
  const setFxRootAddressTx: ContractTransaction = await fxStateChildTunnel.setFxRootTunnel(fxStateRootTunnel.address)
  console.log(' > tx:', getTxExplorerLink(polygonNetworkName, setFxRootAddressTx));

  console.log('Finished deploying tunnel successfully.\n');

  return {
    L1FxTunnel: fxStateRootTunnel,
    L2FxTunnel: fxStateChildTunnel,
  }
}