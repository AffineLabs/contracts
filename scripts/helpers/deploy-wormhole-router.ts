import { ethers } from "hardhat";
import hre from "hardhat";
import {
  Create3Deployer__factory,
  L1WormholeRouter,
  L1WormholeRouter__factory,
  L2WormholeRouter,
  L2WormholeRouter__factory,
} from "../../typechain";
import { addToAddressBookAndDefender } from "../utils/export";
import { totalConfig } from "../utils/config";
import { VaultContracts } from "./deploy-vaults";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";

export interface WormholeRouterContracts {
  l1WormholeRouter: L1WormholeRouter;
  l2WormholeRouter: L2WormholeRouter;
}

export async function deployWormholeRouters(
  config: totalConfig,
  vaults: VaultContracts,
  ethNetworkName: string,
  polygonNetworkName: string,
): Promise<WormholeRouterContracts> {
  const { l1Vault, l2Vault } = vaults;
  /**
   * Deploy l1 wormhole router in eth.
   *
   * */
  console.log("about to deploy l1 wormhole router");
  hre.changeNetwork(ethNetworkName);
  let [deployerSigner] = await ethers.getSigners();

  let create3 = Create3Deployer__factory.connect(config.l1.create3Deployer, deployerSigner);
  const factory = await ethers.getContractFactory("L1WormholeRouter");
  let constructorParams = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint8"],
    [l1Vault.address, config.l1.wormhole, CHAIN_ID_POLYGON],
  );
  // bytecode concat constructor params
  let creationCode = ethers.utils.hexConcat([factory.bytecode, constructorParams]);
  const bytes = ethers.utils.hexZeroPad(`0x${Date.now().toString()}`, 32);
  const salt = ethers.utils.keccak256(bytes);
  let deployTx = await create3.deploy(salt, creationCode, 0);
  await deployTx.wait();
  const routerAddr = await create3.getDeployed(salt);

  await addToAddressBookAndDefender(ethNetworkName, "EthWormholeRouter", "L1WormholeRouter", routerAddr, [], false);
  const l1WormholeRouter = L1WormholeRouter__factory.connect(routerAddr, deployerSigner);
  /**
   * Deploy l2 wormhole router in Polygon.
   *
   * */
  hre.changeNetwork(polygonNetworkName);
  [deployerSigner] = await ethers.getSigners();

  create3 = Create3Deployer__factory.connect(config.l2.create3Deployer, deployerSigner);
  const l2Factory = await ethers.getContractFactory("L2WormholeRouter");
  constructorParams = ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint8"],
    [l2Vault.address, config.l2.wormhole, CHAIN_ID_ETH],
  );
  // bytecode concat constructor params
  creationCode = ethers.utils.hexConcat([l2Factory.bytecode, constructorParams]);
  deployTx = await create3.deploy(salt, creationCode, 0);
  await deployTx.wait();
  const l2WormholeRouter = L2WormholeRouter__factory.connect(routerAddr, deployerSigner);

  await addToAddressBookAndDefender(
    polygonNetworkName,
    "PolygonWormholeRouter",
    "L2WormholeRouter",
    await create3.getDeployed(salt),
    [],
    false,
  );

  return {
    l1WormholeRouter,
    l2WormholeRouter,
  };
}
