import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { Config } from "../../utils/config";
import { L1Vault, L2Vault, Relayer } from "../../typechain";
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
  hre.changeNetwork(ethNetworkName);

  // Generate random wallet and send money to it
  let [governanceSigner] = await ethers.getSigners();
  let wallet = ethers.Wallet.createRandom().connect(ethers.provider);
  console.log("deployer mnemonic: ", wallet.mnemonic);

  let fundTx = await governanceSigner.sendTransaction({
    to: wallet.address,
    value: ethers.utils.parseEther("0.002"),
  });
  await fundTx.wait();

  // deploy deployer from newly funded wallet
  let deployerFactory = await ethers.getContractFactory("Create2Deployer", wallet);
  let deployer = await deployerFactory.deploy();
  await deployer.deployed();

  const l1VaultFactory = await ethers.getContractFactory("L1Vault");
  console.log("about to deploy l1 vault: ", config);

  const l1Vault = (await upgrades.deployProxy(
    l1VaultFactory,
    [l1Governance, config.l1USDC, config.l1worm, deployer.address, config.l1ChainManager, config.l2ERC20Predicate],
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
  [governanceSigner] = await ethers.getSigners();
  const relayerFactory = await ethers.getContractFactory("Relayer", governanceSigner);
  const relayer = await relayerFactory.deploy();
  await relayer.deployed();

  // Generate random wallet and send money to it
  wallet = wallet.connect(ethers.provider);
  fundTx = await governanceSigner.sendTransaction({
    to: wallet.address,
    value: ethers.utils.parseEther("0.02"),
  });
  await fundTx.wait();

  // deploy deployer from newly funded wallet
  deployerFactory = await ethers.getContractFactory("Create2Deployer", wallet);
  deployer = await deployerFactory.deploy();
  await deployer.deployed();

  const l2VaultFactory = await ethers.getContractFactory("L2Vault");
  const withdrawalQueueFactory = await ethers.getContractFactory("WithdrawalQueue");
  const withdrawalQueue = await withdrawalQueueFactory.deploy(l2Governance, config.l2USDC);
  await withdrawalQueue.deployed();
  const l2Vault = (await upgrades.deployProxy(
    l2VaultFactory,
    [
      l2Governance,
      config.l2USDC,
      config.l2worm,
      await getContractAddress(deployer),
      withdrawalQueue,
      9,
      1,
      relayer.address,
      [config.withdrawFee, config.managementFee],
    ],
    { kind: "uups" },
  )) as L2Vault;
  await l2Vault.deployed();
  withdrawalQueue.addVault(l2Vault.address);
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
