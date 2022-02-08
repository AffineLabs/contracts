import { ethers } from "hardhat";
import hre from "hardhat";
import { address } from "../../utils/types";
import { Config } from "../../utils/config";
import { MintableStrategy } from "../../typechain";
import { VaultContracts } from "./deploy-vaults";
import { addToAddressBook } from "../../utils/address-book";
import { ETH_GOERLI, POLYGON_MUMBAI } from "../../utils/constants/blockchain";

export interface StrategyContracts {
  l1: { [strategyName: string]: MintableStrategy };
  l2: { [strategyName: string]: MintableStrategy };
}

export async function deployStrategies(
  governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  vaults: VaultContracts,
  config: Config,
  test: boolean = true,
): Promise<StrategyContracts> {
  if (!test) throw Error("Cannot deploy to mainnet");

  // Deploy Mintable strategy on Polygon
  hre.changeNetwork(polygonNetworkName);
  let [signer] = await ethers.getSigners();

  let stratFactory = await ethers.getContractFactory("MintableStrategy", signer);
  const l2Strategy = (await stratFactory.deploy(vaults.l2Vault.address)) as MintableStrategy;
  await l2Strategy.deployed();
  await addToAddressBook(POLYGON_MUMBAI, `${polygonNetworkName} Mintable Strategy`, "MintableStrategy", l2Strategy);
  console.log("strategy L2: ", l2Strategy.address);

  // Deploy Mintable strategy on ethereum
  hre.changeNetwork(ethNetworkName);
  [signer] = await ethers.getSigners();
  stratFactory = await ethers.getContractFactory("MintableStrategy", signer);
  const l1Strategy = (await stratFactory.deploy(vaults.l1Vault.address)) as MintableStrategy;
  await l1Strategy.deployed();
  await addToAddressBook(ETH_GOERLI, `${ethNetworkName} Mintable Strategy`, "MintableStrategy", l1Strategy);
  console.log("strategy l1: ", l1Strategy.address);

  return {
    l1: { compound: l1Strategy }, // TODO: add real compound strategy
    l2: { aave: l2Strategy },
  };
}
