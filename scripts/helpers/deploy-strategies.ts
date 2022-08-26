import { ethers } from "hardhat";
import hre from "hardhat";
import { L1CompoundStrategy, L2AAVEStrategy } from "typechain";
import { VaultContracts } from "./deploy-vaults";
import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";
import { totalConfig } from "scripts/utils/config";

export interface StrategyContracts {
  l1: { compound: L1CompoundStrategy };
  l2: { aave: L2AAVEStrategy };
}

export async function deployStrategies(
  ethNetworkName: string,
  polygonNetworkName: string,
  vaults: VaultContracts,
  config: totalConfig,
): Promise<StrategyContracts | undefined> {
  console.log("deploying strategies");
  if (ethNetworkName.includes("goerli")) return;

  // Deploy L2AAVEStrat on Polygon
  hre.changeNetwork(polygonNetworkName);
  let [signer] = await ethers.getSigners();

  const aaveConfig = config.l2.aave;
  const stratFactory = await ethers.getContractFactory("L2AAVEStrategy", signer);
  const l2Strategy = await stratFactory.deploy(
    await getContractAddress(vaults.l2Vault),
    aaveConfig.registry,
    aaveConfig.incentivesController,
    aaveConfig.uniRouter,
    aaveConfig.rewardToken,
    aaveConfig.wrappedNative,
  );
  await addToAddressBookAndDefender(polygonNetworkName, `PolygonAAVEStrategy`, "L2AAVEStrategy", l2Strategy, [], false);
  console.log("strategy L2: ", l2Strategy.address);

  // Deploy L1CompoundStrat on ethereum
  hre.changeNetwork(ethNetworkName);
  [signer] = await ethers.getSigners();

  const compConfig = config.l1.compound;
  const compStratFactory = await ethers.getContractFactory("L1CompoundStrategy", signer);
  const l1Strategy = await compStratFactory.deploy(
    await getContractAddress(vaults.l2Vault),
    compConfig.cToken,
    compConfig.comptroller,
    compConfig.uniRouter,
    compConfig.rewardToken,
    compConfig.wrappedNative,
  );
  await l1Strategy.deployed();
  await addToAddressBookAndDefender(ethNetworkName, `EthCompoundStrategy`, "L1CompoundStrategy", l1Strategy, [], false);
  console.log("strategy l1: ", l1Strategy.address);

  return {
    l1: { compound: l1Strategy }, // TODO: add real compound strategy
    l2: { aave: l2Strategy },
  };
}
