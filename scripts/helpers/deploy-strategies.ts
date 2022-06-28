import { ethers } from "hardhat";
import hre from "hardhat";
import { MintableStrategy } from "typechain";
import { VaultContracts } from "./deploy-vaults";
import { addToAddressBookAndDefender } from "../utils/export";
import { ETH_GOERLI, POLYGON_MUMBAI } from "../utils/constants/blockchain";

export interface StrategyContracts {
  l1: { [strategyName: string]: MintableStrategy };
  l2: { [strategyName: string]: MintableStrategy };
}

export async function deployStrategies(
  ethNetworkName: string,
  polygonNetworkName: string,
  vaults: VaultContracts,
  test: boolean = true,
): Promise<StrategyContracts> {
  if (!test) throw Error("Cannot deploy to mainnet");

  // Deploy Mintable strategy on Polygon
  hre.changeNetwork(polygonNetworkName);
  let [signer] = await ethers.getSigners();

  let stratFactory = await ethers.getContractFactory("MintableStrategy", signer);
  const l2Strategy = (await stratFactory.deploy(vaults.l2Vault.address)) as MintableStrategy;
  await l2Strategy.deployed();
  await addToAddressBookAndDefender(
    POLYGON_MUMBAI,
    `PolygonMintableStrategy`,
    "MintableStrategy",
    l2Strategy,
    [],
    false,
  );
  console.log("strategy L2: ", l2Strategy.address);

  // Deploy Mintable strategy on ethereum
  hre.changeNetwork(ethNetworkName);
  [signer] = await ethers.getSigners();
  stratFactory = await ethers.getContractFactory("MintableStrategy", signer);
  const l1Strategy = (await stratFactory.deploy(vaults.l1Vault.address)) as MintableStrategy;
  await l1Strategy.deployed();
  await addToAddressBookAndDefender(ETH_GOERLI, `EthMintableStrategy`, "MintableStrategy", l1Strategy, [], false);
  console.log("strategy l1: ", l1Strategy.address);

  return {
    l1: { compound: l1Strategy }, // TODO: add real compound strategy
    l2: { aave: l2Strategy },
  };
}
