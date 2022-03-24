import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { Config } from "../../utils/config";
import { ICreate2Deployer__factory, L1Vault, L2Vault, Relayer, Staging__factory } from "../../typechain";
import { addToAddressBookAndDefender, getContractAddress } from "../../utils/export";
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
  console.log("about to deploy l1 vault: ", config);
  hre.changeNetwork(ethNetworkName);

  let [deployerSigner] = await ethers.getSigners();

  // Deploy Staging contract
  // padding to unix timestamp (in milliseconds) to 32 bytes
  const rawBytes = ethers.utils.hexZeroPad(`0x${Date.now().toString()}`, 32);
  const salt = ethers.utils.keccak256(rawBytes);
  const stagingCode = (await ethers.getContractFactory("Staging")).bytecode;
  const constructorParams = ethers.utils.defaultAbiCoder.encode(["address"], [await deployerSigner.getAddress()]);

  const stagingCreationCode = ethers.utils.hexConcat([stagingCode, constructorParams]); // bytecode concat constructor params

  let create2 = ICreate2Deployer__factory.connect(config.create2Deployer, deployerSigner);
  let stagindDeployTx = await create2.deploy(0, salt, stagingCreationCode);
  await stagindDeployTx.wait();

  const stagingAddr = await create2.computeAddress(salt, ethers.utils.keccak256(stagingCreationCode));

  const l1VaultFactory = await ethers.getContractFactory("L1Vault");

  // Deploy vault
  const l1Vault = (await upgrades.deployProxy(
    l1VaultFactory,
    [l1Governance, config.l1USDC, config.l1worm, stagingAddr, config.l1ChainManager, config.l2ERC20Predicate],
    { kind: "uups" },
  )) as L1Vault;
  await l1Vault.deployed();
  await addToAddressBookAndDefender(ETH_GOERLI, `EthAlpSave`, "L1Vault", l1Vault);
  logContractDeploymentInfo(ethNetworkName, "L1Vault", l1Vault);

  // Initialize staging
  let staging = Staging__factory.connect(stagingAddr, deployerSigner);
  let stagingInitTx = await staging.initialize(
    await getContractAddress(l1Vault),
    config.l1worm,
    config.l1USDC,
    config.l1ChainManager,
  );
  await stagingInitTx.wait();

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

  // Deploy staging
  create2 = ICreate2Deployer__factory.connect(config.create2Deployer, deployerSigner);
  stagindDeployTx = await create2.deploy(0, salt, stagingCreationCode);
  await stagindDeployTx.wait();

  const l2VaultFactory = await ethers.getContractFactory("L2Vault");
  const l2Vault = (await upgrades.deployProxy(
    l2VaultFactory,
    [
      l2Governance,
      config.l2USDC,
      config.l2worm,
      stagingAddr,
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

  // Initialize staging
  staging = Staging__factory.connect(stagingAddr, deployerSigner);
  stagingInitTx = await staging.initialize(
    await getContractAddress(l2Vault),
    config.l2worm,
    config.l2USDC,
    ethers.constants.AddressZero, // there is no root chain manager in polygon
  );
  await stagingInitTx.wait();

  // Initialize relayer
  const initTx = await relayer.initialize(config.biconomyForwarder, l2Vault.address);
  await initTx.wait();

  return {
    l1Vault,
    l2Vault,
    relayer,
  };
}
