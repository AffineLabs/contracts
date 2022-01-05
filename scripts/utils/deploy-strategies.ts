import { ethers } from "hardhat";
import { Contract } from "ethers";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { address } from "../../utils/types";
import scriptUtils from "./index";
import { Config } from "../../utils/config";

export interface StrategyContracts {
  l1: { [strategyName: string]: Contract };
  l2: { [strategyName: string]: Contract };
}

export async function deployStrategies(
  governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
  test: boolean = true,
): Promise<StrategyContracts> {
  // Deploy vault in eth.
  hre.changeNetwork(polygonNetworkName);

  const [signer] = await ethers.getSigners();

  if (!test) throw Error("Cannot deploy to mainnet");

  // deploy MintableStrategy
  const stratFactory = await scriptUtils.getContractFactory("MintableStrategy", signer);
  const strategy = await stratFactory.deploy();
  await strategy.wait();
  console.log("strategy: ", strategy.address);
  return {
    l1: { Compound: strategy }, // TODO: add compound strategy
    l2: { AAVE: strategy },
  };
}
