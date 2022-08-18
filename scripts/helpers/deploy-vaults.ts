import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../utils/bc-explorer-links";
import { Config } from "../utils/config";
import {
  ICreate2Deployer__factory,
  L1Vault,
  L2Vault,
  BridgeEscrow__factory,
  EmergencyWithdrawalQueue,
} from "../../typechain";
import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";
import { ETH_GOERLI, POLYGON_MUMBAI } from "../utils/constants/blockchain";
import { address } from "../utils/types";
import { WormholeRouterContracts } from "./deploy-wormhole-router";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";

export interface VaultContracts {
  l1Vault: L1Vault;
  l2Vault: L2Vault;
  emergencyWithdrawalQueue: EmergencyWithdrawalQueue;
}

export async function deployVaults(
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
  wormholeRouters: WormholeRouterContracts,
): Promise<VaultContracts> {
  /**
   * Deploy vault in eth.
   *
   * */
  console.log("about to deploy l1 vault: ", config);
  hre.changeNetwork(ethNetworkName);

  let [deployerSigner] = await ethers.getSigners();

  // Deploy BridgeEscrow contract
  // padding to unix timestamp (in milliseconds) to 32 bytes
  const rawBytes = ethers.utils.hexZeroPad(`0x${Date.now().toString()}`, 32);
  const salt = ethers.utils.keccak256(rawBytes);
  const bridgeEscrowCode = (await ethers.getContractFactory("BridgeEscrow")).bytecode;
  const constructorParams = ethers.utils.defaultAbiCoder.encode(["address"], [await deployerSigner.getAddress()]);

  const bridgeEscrowCreationCode = ethers.utils.hexConcat([bridgeEscrowCode, constructorParams]); // bytecode concat constructor params

  let create2 = ICreate2Deployer__factory.connect(config.create2Deployer, deployerSigner);
  let stagindDeployTx = await create2.deploy(0, salt, bridgeEscrowCreationCode);
  await stagindDeployTx.wait();

  const bridgeEscrowAddr = await create2.computeAddress(salt, ethers.utils.keccak256(bridgeEscrowCreationCode));

  const l1VaultFactory = await ethers.getContractFactory("L1Vault");

  // Deploy vault
  const l1Vault = (await upgrades.deployProxy(
    l1VaultFactory,
    [
      l1Governance,
      config.l1USDC,
      wormholeRouters.l1WormholeRouter.address,
      bridgeEscrowAddr,
      config.l1ChainManager,
      config.l2ERC20Predicate,
    ],
    { kind: "uups" },
  )) as L1Vault;
  await l1Vault.deployed();
  await addToAddressBookAndDefender(ETH_GOERLI, `EthAlpSave`, "L1Vault", l1Vault);
  logContractDeploymentInfo(ethNetworkName, "L1Vault", l1Vault);

  console.log("Initializing L1 Escrow: ");

  // Initialize bridgeEscrow
  let bridgeEscrow = BridgeEscrow__factory.connect(bridgeEscrowAddr, deployerSigner);
  let bridgeEscrowInitTx = await bridgeEscrow.initialize(
    await getContractAddress(l1Vault),
    wormholeRouters.l1WormholeRouter.address,
    config.l1USDC,
    config.l1ChainManager,
  );
  await bridgeEscrowInitTx.wait();

  /**
   * Deploy vault in Polygon.
   *
   * */
  hre.changeNetwork(polygonNetworkName);
  [deployerSigner] = await ethers.getSigners();

  // Deploy bridgeEscrow
  console.log("Deploying L2 Escrow");
  create2 = ICreate2Deployer__factory.connect(config.create2Deployer, deployerSigner);
  stagindDeployTx = await create2.deploy(0, salt, bridgeEscrowCreationCode);
  await stagindDeployTx.wait();

  const emergencyWithdrawalQueueFactory = await ethers.getContractFactory("EmergencyWithdrawalQueue");
  const emergencyWithdrawalQueue = await emergencyWithdrawalQueueFactory.deploy(l2Governance);

  const l2VaultFactory = await ethers.getContractFactory("L2Vault");
  const l2Vault = (await upgrades.deployProxy(
    l2VaultFactory,
    [
      l2Governance,
      config.l2USDC,
      wormholeRouters.l2WormholeRouter.address,
      bridgeEscrowAddr,
      emergencyWithdrawalQueue.address,
      config.forwarder,
      9,
      1,
      [config.withdrawFee, config.managementFee],
    ],
    { kind: "uups" },
  )) as L2Vault;
  await l2Vault.deployed();

  await emergencyWithdrawalQueue.linkVault(l2Vault.address);
  await addToAddressBookAndDefender(POLYGON_MUMBAI, `PolygonAlpSave`, "L2Vault", l2Vault);
  logContractDeploymentInfo(polygonNetworkName, "L2Vault", l2Vault);

  // Initialize bridgeEscrow
  bridgeEscrow = BridgeEscrow__factory.connect(bridgeEscrowAddr, deployerSigner);
  bridgeEscrowInitTx = await bridgeEscrow.initialize(
    await getContractAddress(l2Vault),
    wormholeRouters.l2WormholeRouter.address,
    config.l2USDC,
    ethers.constants.AddressZero, // there is no root chain manager in polygon
  );
  await bridgeEscrowInitTx.wait();

  // Initialize wormhole routers
  await wormholeRouters.l1WormholeRouter.initialize(
    config.l1worm,
    l1Vault.address,
    wormholeRouters.l2WormholeRouter.address,
    CHAIN_ID_POLYGON,
  );
  await wormholeRouters.l2WormholeRouter.initialize(
    config.l2worm,
    l2Vault.address,
    wormholeRouters.l1WormholeRouter.address,
    CHAIN_ID_ETH,
  );

  return {
    l1Vault,
    l2Vault,
    emergencyWithdrawalQueue,
  };
}
