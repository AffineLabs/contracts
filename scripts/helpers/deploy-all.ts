import { deployVaults, VaultContracts } from "./deploy-vaults";
import { Config } from "../utils/config";
import { deployStrategies, StrategyContracts } from "./deploy-strategies";
import { deployBasket } from "./deploy-btc-eth";
import { address } from "../utils/types";
import { MintableToken__factory, TwoAssetBasket } from "../../typechain";
import { ethers } from "hardhat";
import hre from "hardhat";
import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";
import { POLYGON_MUMBAI } from "../utils/constants/blockchain";
import { sign } from "crypto";
import { deployWormholeRouters } from "./deploy-wormhole-router";

export interface AllContracts {
  vaults: VaultContracts;
  strategies: StrategyContracts;
  basket: TwoAssetBasket;
}

export async function deployAll(
  l1Governance: address,
  l2Governance: address,
  ethNetworkName: string,
  polygonNetworkName: string,
  config: Config,
): Promise<AllContracts> {
  const wormholeRouters = await deployWormholeRouters(ethNetworkName, polygonNetworkName);
  const vaults = await deployVaults(
    l1Governance,
    l2Governance,
    ethNetworkName,
    polygonNetworkName,
    config,
    wormholeRouters,
  );
  const strategies = await deployStrategies(ethNetworkName, polygonNetworkName, vaults);

  // TODO: Consider strategies. We can't add strategies anymore since the timelock address is the governance address
  // In tests we can simply use hardhat's mocking abilities.

  // console.log("Adding strategies to vault...");
  // add L2 strategies
  // changeNetwork(polygonNetworkName);
  // let [governanceSigner] = await ethers.getSigners();
  // await vaults.l2Vault.connect(governanceSigner).addStrategy(strategies.l2.aave.address);

  // add L1 strategies
  // changeNetwork(ethNetworkName);
  // [governanceSigner] = await ethers.getSigners();
  // await vaults.l1Vault.connect(governanceSigner).addStrategy(strategies.l1.compound.address);
  // console.log("Strategies added");
  hre.changeNetwork(polygonNetworkName);
  const basket = await deployBasket(config);

  // Add some transactions
  // TODO: make sure this only runs when we are in testnet mode
  const [signer] = await ethers.getSigners();
  const usdc = MintableToken__factory.connect(config.l2USDC, signer);
  const oneUsdc = ethers.BigNumber.from(10).pow(6);
  const maxUint = ethers.BigNumber.from(2).pow(256).sub(1);
  let tx = await usdc.approve(await getContractAddress(vaults.l2Vault), maxUint);
  await tx.wait();
  tx = await usdc.approve(await getContractAddress(basket), maxUint);
  await tx.wait();

  tx = await vaults.l2Vault.deposit(oneUsdc.mul(2));
  await tx.wait();
  tx = await vaults.l2Vault.withdraw(oneUsdc);
  await tx.wait();

  const signerAddr = await signer.getAddress();
  tx = await basket.deposit(oneUsdc.mul(2), signerAddr);
  await tx.wait();
  tx = await basket.withdraw(oneUsdc.div(10), signerAddr, signerAddr);
  await tx.wait();

  // Add usdc to address book, TODO: handle the production version of this
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "PolygonUSDC", "MintableToken", usdc.address);
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "Forwarder", "Forwarder", config.forwarder);

  return {
    vaults,
    strategies,
    basket,
  };
}
