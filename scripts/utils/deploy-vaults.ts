import { ethers, upgrades } from "hardhat";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { address } from "../../utils/types";
import { Config } from "../../utils/config";
import { L1Vault, L2Vault } from "../../typechain";
import { addToAddressBookAndDefender, getContractAddress } from "../../utils/export";
import { ETH_GOERLI, POLYGON_MUMBAI } from "../../utils/constants/blockchain";

export interface VaultContracts {
  l1Vault: L1Vault;
  l2Vault: L2Vault;
}

export async function deployVaults(
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<VaultContracts> {
  // Deploy vault in eth.
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
  await addToAddressBookAndDefender(ETH_GOERLI, `${ethNetworkName} Alpine Save`, "L1Vault", l1Vault);
  logContractDeploymentInfo(ethNetworkName, "L1Vault", l1Vault);

  // Deploy vault in polygon.
  hre.changeNetwork(polygonNetworkName);

  // Generate random wallet and send money to it
  [governanceSigner] = await ethers.getSigners();
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
  const l2Vault = (await upgrades.deployProxy(
    l2VaultFactory,
    [
      l2Governance,
      config.l2USDC,
      config.l2worm,
      await getContractAddress(deployer),
      9,
      1,
      config.biconomyForwarder,
      config.withdrawFee,
    ],
    { kind: "uups" },
  )) as L2Vault;
  await l2Vault.deployed();
  await addToAddressBookAndDefender(POLYGON_MUMBAI, `${polygonNetworkName} Alpine Save`, "L2Vault", l2Vault);
  await addToAddressBookAndDefender(POLYGON_MUMBAI, `${polygonNetworkName} Relayer`, "Relayer", await l2Vault.relayer());
  logContractDeploymentInfo(polygonNetworkName, "L2Vault", l2Vault);

  return {
    l1Vault,
    l2Vault,
  };
}
