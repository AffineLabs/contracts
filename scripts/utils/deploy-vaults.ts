import { ethers } from "hardhat";
import { Contract } from "ethers";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../../utils/bc-explorer-links";
import { address } from "../../utils/types";
import scriptUtils from "./index";
import { Config } from "../../utils/config";

export interface VaultContracts {
  l1Vault: Contract;
  l2Vault: Contract;
}

export async function deployVaults(
  governance: address,
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
  let deployerFactory = await scriptUtils.getContractFactory("Create2Deployer", wallet);
  let deployer = await deployerFactory.deploy();
  await deployer.deployed();

  const l1VaultFactory = await scriptUtils.getContractFactory("L1Vault");
  console.log("about to deploy l1 vault: ", config);

  const l1Vault = await l1VaultFactory.deploy(
    governance,
    config.l1USDC,
    config.l1worm,
    deployer.address,
    config.l1ChainManager,
    config.l2ERC20Predicate,
  );
  await l1Vault.deployed();
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
  deployerFactory = await scriptUtils.getContractFactory("Create2Deployer", wallet);
  deployer = await deployerFactory.deploy();
  await deployer.deployed();

  const l2VaultFactory = await scriptUtils.getContractFactory("L2Vault");
  const l2Vault = await l2VaultFactory.deploy(governance, config.l2USDC, config.l2worm, deployer.address, 9, 1);
  await l2Vault.deployed();
  logContractDeploymentInfo(polygonNetworkName, "L2Vault", l2Vault);

  return {
    l1Vault,
    l2Vault,
  };
}
