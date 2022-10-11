import { ethers } from "hardhat";
import hre from "hardhat";
import { mainnetConfig } from "./utils/config";
import { ICreate2Deployer__factory, BridgeEscrow__factory, L1WormholeRouter, L2WormholeRouter } from "../typechain";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";

const ETH_ALP_SAVE = "0x8C1445315a5345E1406b13DE8178Afc6Fa1c6B2E"; // "0x7331aD312BAF6CFb127a84DbA077b72295cFEB28";
const POLYGON_ALP_SAVE = "0x086afAa8b35E0DAE1A779103A1A48fC2E05Ab928"; // "0xaB4ea6763fb78f1DdAB34101ccb460c1768B4f3A";

async function deployNewWHRouterAndBridgeEscrow() {
  const bridgeEscrowCode = BridgeEscrow__factory.bytecode;
  const rawBytes = ethers.utils.hexZeroPad(`0x${Date.now().toString()}`, 32);
  const salt = ethers.utils.keccak256(rawBytes);
  const deployerSignerAddress = (await ethers.getSigners())[0].address;
  const constructorParams = ethers.utils.defaultAbiCoder.encode(["address"], [deployerSignerAddress]);
  const bridgeEscrowCreationCode = ethers.utils.hexConcat([bridgeEscrowCode, constructorParams]);

  hre.changeNetwork("eth-goerli");
  const [ethDeployerSigner] = await ethers.getSigners();
  const ethCreate2 = ICreate2Deployer__factory.connect(mainnetConfig.l1.create2Deployer, ethDeployerSigner);
  console.log("[Eth] Deploying bridge escrow");
  const ethBridgeEscrowDeployTx = await ethCreate2.deploy(0, salt, bridgeEscrowCreationCode);
  await ethBridgeEscrowDeployTx.wait();
  const ethBridgeEscrowAddr = await ethCreate2.computeAddress(salt, ethers.utils.keccak256(bridgeEscrowCreationCode));
  const ethBridgeEscrow = BridgeEscrow__factory.connect(ethBridgeEscrowAddr, ethDeployerSigner);

  const ethWormholeRouterFactory = await ethers.getContractFactory("L1WormholeRouter");
  console.log("[Eth] Deploying wormhole router");
  const ethWormholeRouter = (await ethWormholeRouterFactory.deploy()) as L1WormholeRouter;

  const ethAlpSaveImplFactory = await ethers.getContractFactory("L1Vault");
  console.log("[Eth] Deploy Alp Save");
  const ethAlpSaveImpl = await ethAlpSaveImplFactory.deploy();

  hre.changeNetwork("polygon-mumbai");
  const [polygonDeployerSigner] = await ethers.getSigners();
  const polygonCreate2 = ICreate2Deployer__factory.connect(mainnetConfig.l2.create2Deployer, polygonDeployerSigner);
  console.log("[Polygon] Deploying bridge escrow");
  const polygonBridgeEscrowDeployTx = await polygonCreate2.deploy(0, salt, bridgeEscrowCreationCode);
  await polygonBridgeEscrowDeployTx.wait();
  const polygonBridgeEscrowAddr = await polygonCreate2.computeAddress(
    salt,
    ethers.utils.keccak256(bridgeEscrowCreationCode),
  );
  const polygonBridgeEscrow = BridgeEscrow__factory.connect(polygonBridgeEscrowAddr, polygonDeployerSigner);

  const polygonWormholeRouterFactory = await ethers.getContractFactory("L2WormholeRouter");
  console.log("[Polygon] Deploying wormhole router");
  const polygonWormholeRouter = (await polygonWormholeRouterFactory.deploy()) as L2WormholeRouter;

  const polygonAlpSaveImplFactory = await ethers.getContractFactory("L2Vault");
  console.log("[Polygon] Deploy Alp Save");
  const polygonAlpSaveImpl = await polygonAlpSaveImplFactory.deploy();

  // Initialize
  console.log("[Eth] Initializing wormhole router");
  await ethWormholeRouter.initialize(
    mainnetConfig.l1.wormhole,
    ETH_ALP_SAVE,
    polygonWormholeRouter.address,
    CHAIN_ID_POLYGON,
  );

  console.log("[Polygon] Initializing wormhole router");
  await polygonWormholeRouter.initialize(
    mainnetConfig.l2.wormhole,
    POLYGON_ALP_SAVE,
    ethWormholeRouter.address,
    CHAIN_ID_ETH,
  );

  console.log("[Eth] Initializing bridge escrow");
  await ethBridgeEscrow.initialize(
    ETH_ALP_SAVE,
    ethWormholeRouter.address,
    mainnetConfig.l1.usdc,
    mainnetConfig.l1.chainManager,
  );

  console.log("[Polygon] Initializing bridge escrow");
  await polygonBridgeEscrow.initialize(
    POLYGON_ALP_SAVE,
    polygonWormholeRouter.address,
    mainnetConfig.l2.usdc,
    ethers.constants.AddressZero, // there is no root chain manager in polygon
  );

  console.log("Eth Alp Save Impl:", ethAlpSaveImpl.address);
  console.log("Polygon Alp Save Impl:", polygonAlpSaveImpl.address);

  console.log("Eth WH Router:", ethWormholeRouter.address);
  console.log("Polygon WH Router:", polygonWormholeRouter.address);

  console.log("Eth Bridge Escrow:", ethBridgeEscrow.address);
  console.log("Polygon Bridge Escrow:", polygonBridgeEscrow.address);
}

deployNewWHRouterAndBridgeEscrow()
  .then(() => {
    console.log("Path completed!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
