import { ethers } from "hardhat";
import hre from "hardhat";
import { mainnetConfig } from "./utils/config";
import { ICreate2Deployer__factory, BridgeEscrow__factory, L1WormholeRouter, L2WormholeRouter } from "../typechain";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";

const ETH_ALP_SAVE = "0x7331aD312BAF6CFb127a84DbA077b72295cFEB28";
const POLYGON_ALP_SAVE = "0xaB4ea6763fb78f1DdAB34101ccb460c1768B4f3A";

async function deployNewWHRouterAndBridgeEscrow() {
  const bridgeEscrowCode = BridgeEscrow__factory.bytecode;
  const rawBytes = ethers.utils.hexZeroPad(`0x${Date.now().toString()}`, 32);
  const salt = ethers.utils.keccak256(rawBytes);
  let deployerSignerAddress = (await ethers.getSigners())[0].address;
  const constructorParams = ethers.utils.defaultAbiCoder.encode(["address"], [deployerSignerAddress]);
  const bridgeEscrowCreationCode = ethers.utils.hexConcat([bridgeEscrowCode, constructorParams]);

  hre.changeNetwork("eth-mainnet");
  let [ethDeployerSigner] = await ethers.getSigners();
  let ethCreate2 = ICreate2Deployer__factory.connect(mainnetConfig.l1.create2Deployer, ethDeployerSigner);
  let ethBridgeEscrowDeployTx = await ethCreate2.deploy(0, salt, bridgeEscrowCreationCode);
  await ethBridgeEscrowDeployTx.wait();
  const ethBridgeEscrowAddr = await ethCreate2.computeAddress(salt, ethers.utils.keccak256(bridgeEscrowCreationCode));
  let ethBridgeEscrow = BridgeEscrow__factory.connect(ethBridgeEscrowAddr, ethDeployerSigner);

  const ethWormholeRouterFactory = await ethers.getContractFactory("L1WormholeRouter");
  const ethWormholeRouter = (await ethWormholeRouterFactory.deploy()) as L1WormholeRouter;

  hre.changeNetwork("polygon-mainnet");
  let [polygonDeployerSigner] = await ethers.getSigners();
  let polygonCreate2 = ICreate2Deployer__factory.connect(mainnetConfig.l2.create2Deployer, polygonDeployerSigner);
  let polygonBridgeEscrowDeployTx = await polygonCreate2.deploy(0, salt, bridgeEscrowCreationCode);
  await polygonBridgeEscrowDeployTx.wait();
  const polygonBridgeEscrowAddr = await polygonCreate2.computeAddress(
    salt,
    ethers.utils.keccak256(bridgeEscrowCreationCode),
  );
  let polygonBridgeEscrow = BridgeEscrow__factory.connect(polygonBridgeEscrowAddr, polygonDeployerSigner);

  const polygonWormholeRouterFactory = await ethers.getContractFactory("L2WormholeRouter");
  const polygonWormholeRouter = (await polygonWormholeRouterFactory.deploy()) as L2WormholeRouter;

  await ethWormholeRouter.initialize(
    mainnetConfig.l1.wormhole,
    ETH_ALP_SAVE,
    polygonWormholeRouter.address,
    CHAIN_ID_POLYGON,
  );
  await polygonWormholeRouter.initialize(
    mainnetConfig.l2.wormhole,
    POLYGON_ALP_SAVE,
    ethWormholeRouter.address,
    CHAIN_ID_ETH,
  );
  await ethBridgeEscrow.initialize(
    ETH_ALP_SAVE,
    ethWormholeRouter.address,
    mainnetConfig.l1.usdc,
    mainnetConfig.l1.chainManager,
  );
  await polygonBridgeEscrow.initialize(
    POLYGON_ALP_SAVE,
    polygonWormholeRouter.address,
    mainnetConfig.l2.usdc,
    ethers.constants.AddressZero, // there is no root chain manager in polygon
  );
}
