import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { Config } from "../../utils/config";
import { ICreate2Deployer__factory, L1Vault, L2Vault, Relayer } from "../../typechain";
import { addToAddressBookAndDefender } from "../../utils/export";
import { ETH_GOERLI, POLYGON_MUMBAI } from "../../utils/constants/blockchain";
import { address } from "../../utils/types";

export interface VaultContracts {
  l1Vault: L1Vault;
  l2Vault: L2Vault;
  relayer: Relayer;
}

export async function deployVaults(
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<VaultContracts> {
  /**
   * Deploy vault in eth.
   *
   * */
  hre.changeNetwork(ethNetworkName);

  let [deployerSigner] = await ethers.getSigners();

  // Deploy Staging contract on L1

  // padding to unix timestamp (in milliseconds) to 32
  const rawBytes = ethers.utils.hexZeroPad(`0x${Date.now().toString()}`, 32);
  const salt = ethers.utils.keccak256(rawBytes);
  console.log({ salt });

  const l1VaultFactory = await ethers.getContractFactory("L1Vault");
  console.log("about to deploy l1 vault: ", config);

  const l1Vault = (await upgrades.deployProxy(
    l1VaultFactory,
    [
      l1Governance,
      config.l1USDC,
      config.l1worm,
      config.create2Deployer,
      salt,
      config.l1ChainManager,
      config.l2ERC20Predicate,
    ],
    { kind: "uups" },
  )) as L1Vault;
  await l1Vault.deployed();
  await addToAddressBookAndDefender(ETH_GOERLI, `EthAlpSave`, "L1Vault", l1Vault);
  logContractDeploymentInfo(ethNetworkName, "L1Vault", l1Vault);

  /**
   * Deploy vault in Polygon.
   *
   * */
  hre.changeNetwork(polygonNetworkName);

  // Deploy relayer
  [deployerSigner] = await ethers.getSigners();
  const relayerFactory = await ethers.getContractFactory("Relayer", deployerSigner);
  const relayer = await relayerFactory.deploy();
  await relayer.deployed();

  const l2VaultFactory = await ethers.getContractFactory("L2Vault");
  const l2Vault = (await upgrades.deployProxy(
    l2VaultFactory,
    [
      l2Governance,
      config.l2USDC,
      config.l2worm,
      config.create2Deployer,
      salt,
      9,
      1,
      relayer.address,
      [config.withdrawFee, config.managementFee],
    ],
    { kind: "uups" },
  )) as L2Vault;
  await l2Vault.deployed();
  await addToAddressBookAndDefender(POLYGON_MUMBAI, `PolygonAlpSave`, "L2Vault", l2Vault);
  await addToAddressBookAndDefender(POLYGON_MUMBAI, `PolygonRelayer`, "Relayer", await l2Vault.relayer());
  logContractDeploymentInfo(polygonNetworkName, "L2Vault", l2Vault);

  // Initialize relayer
  const initTx = await relayer.initialize(config.biconomyForwarder, l2Vault.address);
  await initTx.wait();

  return {
    l1Vault,
    l2Vault,
    relayer,
  };
}
