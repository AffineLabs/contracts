import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../utils/bc-explorer-links";
import { totalConfig } from "../utils/config";
import {
  Create3Deployer__factory,
  L1Vault,
  L2Vault,
  BridgeEscrow__factory,
  EmergencyWithdrawalQueue,
  BridgeEscrow,
  EmergencyWithdrawalQueue__factory,
  Forwarder,
} from "../../typechain";
import { addToAddressBookAndDefender } from "../utils/export";

export interface VaultContracts {
  l1Vault: L1Vault;
  l2Vault: L2Vault;
  emergencyWithdrawalQueue: EmergencyWithdrawalQueue;
  l1BridgeEscrow: BridgeEscrow;
  l2BridgeEscrow: BridgeEscrow;
}

export async function deployVaults(
  ethNetworkName: string,
  polygonNetworkName: string,
  config: totalConfig,
  forwarder: Forwarder,
): Promise<VaultContracts> {
  /**
   * Deploy vault in eth.
   *
   * */
  console.log("about to deploy l1 vault: ", config);
  hre.changeNetwork(ethNetworkName);

  let [deployerSigner] = await ethers.getSigners();

  // We need the bridgeEscrow and wormhole router addresses
  // Padding to unix timestamp (in milliseconds) to 32 bytes
  const escrowBytes = ethers.utils.hexZeroPad(`0x${Date.now().toString()}`, 32);
  const escrowSalt = ethers.utils.keccak256(escrowBytes);
  const routerBytes = ethers.utils.hexZeroPad(`0x${(Date.now() + 10).toString()}`, 32);
  const routerSalt = ethers.utils.keccak256(routerBytes);

  let create3 = Create3Deployer__factory.connect(config.l1.create3Deployer, deployerSigner);
  const escrowAddr = await create3.getDeployed(escrowSalt);
  const routerAddr = await create3.getDeployed(routerSalt);

  // Deploy vault
  //  Delegaecall is okay because we only delegatecall into the current contract (multicall)
  // See https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#potentially-unsafe-operations for more

  const l1VaultFactory = await ethers.getContractFactory("L1Vault");
  const l1Vault = (await upgrades.deployProxy(
    l1VaultFactory,
    [config.l1.governance, config.l1.usdc, routerAddr, escrowAddr, config.l1.chainManager, config.l1.ERC20Predicate],
    {
      kind: "uups",
      unsafeAllow: ["delegatecall"],
    },
  )) as L1Vault;
  await l1Vault.deployed();
  await addToAddressBookAndDefender(ethNetworkName, `EthAlpSave`, "L1Vault", l1Vault);
  logContractDeploymentInfo(ethNetworkName, "L1Vault", l1Vault);

  // Deploy BridgeEscrow contract
  let escrowFactory = await ethers.getContractFactory("BridgeEscrow");
  let constructorParams = ethers.utils.defaultAbiCoder.encode(
    ["address", "address"],
    [l1Vault.address, config.l1.chainManager],
  );
  // bytecode concat constructor params
  let bridgeEscrowCreationCode = ethers.utils.hexConcat([escrowFactory.bytecode, constructorParams]);

  let escrowTx = await create3.deploy(escrowSalt, bridgeEscrowCreationCode, 0);
  await escrowTx.wait();
  const l1BridgeEscrow = BridgeEscrow__factory.connect(escrowAddr, deployerSigner);

  /**
   * Deploy vault in Polygon.
   *
   * */
  hre.changeNetwork(polygonNetworkName);
  [deployerSigner] = await ethers.getSigners();
  create3 = Create3Deployer__factory.connect(config.l2.create3Deployer, deployerSigner);

  // Get ewq address
  const ewqBytes = ethers.utils.hexZeroPad(`0x${(Date.now() + 30).toString()}`, 32);
  const ewqSalt = ethers.utils.keccak256(ewqBytes);
  const ewqAddress = await create3.getDeployed(ewqSalt);

  // Deploy vault
  const l2VaultFactory = await ethers.getContractFactory("L2Vault");
  const l2Vault = (await upgrades.deployProxy(
    l2VaultFactory,
    [
      config.l2.governance,
      config.l2.usdc,
      routerAddr,
      escrowAddr,
      ewqAddress,
      forwarder.address,
      9,
      1,
      [config.l2.withdrawFee, config.l2.managementFee],
    ],
    {
      kind: "uups",
      unsafeAllow: ["delegatecall"],
    },
  )) as L2Vault;
  await l2Vault.deployed();

  // Deploy BridgeEscrow contract
  escrowFactory = await ethers.getContractFactory("BridgeEscrow");
  constructorParams = ethers.utils.defaultAbiCoder.encode(
    ["address", "address"],
    [l2Vault.address, ethers.constants.AddressZero],
  );
  // bytecode concat constructor params
  escrowTx = await create3.deploy(escrowSalt, ethers.utils.hexConcat([escrowFactory.bytecode, constructorParams]), 0);
  await escrowTx.wait();
  const l2BridgeEscrow = BridgeEscrow__factory.connect(escrowAddr, deployerSigner);

  // Deploy EWQ
  const ewqFactory = await ethers.getContractFactory("EmergencyWithdrawalQueue");
  constructorParams = ethers.utils.defaultAbiCoder.encode(["address"], [l2Vault.address]);
  const ewqCreationCode = ethers.utils.hexConcat([ewqFactory.bytecode, constructorParams]);
  const ewqTx = await create3.deploy(ewqSalt, ewqCreationCode, 0);
  await ewqTx.wait();
  const emergencyWithdrawalQueue = EmergencyWithdrawalQueue__factory.connect(ewqAddress, deployerSigner);

  await addToAddressBookAndDefender(polygonNetworkName, `PolygonAlpSave`, "L2Vault", l2Vault);
  logContractDeploymentInfo(polygonNetworkName, "L2Vault", l2Vault);

  return {
    l1Vault,
    l2Vault,
    emergencyWithdrawalQueue,
    l1BridgeEscrow,
    l2BridgeEscrow,
  };
}
