import { TransactionResponse } from "@ethersproject/providers";
import { Contract, ethers, Wallet } from "ethers";
import utils from "../test/utils";
import { resolve } from "path";
import { readFileSync } from "fs";

import { REBALANCE_CONFIG } from "./utils/config";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";

const abiDir = resolve(__dirname, "../abi");
const l1WormholeRouterABI = JSON.parse(readFileSync(`${abiDir}/L1WormholeRouter.abi`).toString());
const l2WormholeRouterABI = JSON.parse(readFileSync(`${abiDir}/L2WormholeRouter.abi`).toString());
const l1VaultABI = JSON.parse(readFileSync(`${abiDir}/L1Vault.abi`).toString());
const l2VaultABI = JSON.parse(readFileSync(`${abiDir}/L2Vault.abi`).toString());

const bridgeEscrowABI = JSON.parse(readFileSync(`${abiDir}/BridgeEscrow.abi`).toString());
const wormholeABI = JSON.parse(readFileSync(`${abiDir}/IWormhole.abi`).toString());
const usdcABI = JSON.parse(readFileSync(`${abiDir}/IERC20.abi`).toString());

async function main() {
  const {
    l1WormholeRouterAddr,
    l2WormholeRouterAddr,
    l1VaultAddr,
    l2VaultAddr,
    mnemonic,
    ethAlchemyURL,
    polygonAlchemyURL,
  } = REBALANCE_CONFIG;
  const goerliProvider = new ethers.providers.JsonRpcProvider(ethAlchemyURL);
  const mumbaiProvider = new ethers.providers.JsonRpcProvider(polygonAlchemyURL);

  const ethWallet = Wallet.fromMnemonic(mnemonic).connect(goerliProvider);
  const polygonWallet = Wallet.fromMnemonic(mnemonic).connect(mumbaiProvider);

  console.log("Rebalancer address:", ethWallet.address);

  const l1Vault = new Contract(l1VaultAddr, l1VaultABI, ethWallet);
  const l2Vault = new Contract(l2VaultAddr, l2VaultABI, polygonWallet);

  // Initiate possible rebalance
  let tx: TransactionResponse = await l1Vault.sendTVL();
  await tx.wait();

  // Receive TVL
  const l1WormholeRouter = new Contract(await l1WormholeRouterAddr, l1WormholeRouterABI, ethWallet);
  const l2WormholeRouter = new Contract(await l2WormholeRouterAddr, l2WormholeRouterABI, polygonWallet);
  const l1wormhole = new Contract(await l1Vault.wormhole(), wormholeABI, ethWallet);
  const l2wormhole = new Contract(await l2Vault.wormhole(), wormholeABI, polygonWallet);

  let l1VaultSeq = await l1wormhole.nextSequence(l1WormholeRouterAddr);
  const tvlVAA = await utils.getVAA(l1WormholeRouterAddr, String(l1VaultSeq - 1), CHAIN_ID_ETH);
  tx = await l2Vault.receiveTVL(tvlVAA);
  await tx.wait();

  const l2BridgeEscrow = new Contract(await l2Vault.bridgeEscrow(), bridgeEscrowABI, polygonWallet);

  // If L2->L1 bridge is locked, then wait for transfer to complete and clear funds on L1
  // otherwise receive message on L1

  const sendingMoneyToL1 = !(await l2Vault.canTransferToL1());
  if (sendingMoneyToL1) {
    console.log("\n\nSending money to L1");
    const messageProof = await utils.waitForL2MessageProof(
      "https://apis.matic.network/api/v1/mumbai",
      tx.hash,
      "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", // ERC20 transfer event sig.
    );
    // Get VAA
    let l2VaultSeq = await l2wormhole.nextSequence(l2WormholeRouterAddr);
    const transferVAA = await utils.getVAA(l2WormholeRouterAddr, String(l2VaultSeq - 1), CHAIN_ID_POLYGON, 64);

    // Post VAA to clear funds
    tx = await l1WormholeRouter.receiveFunds(transferVAA, ethers.utils.arrayify(messageProof));
    await tx.wait();
  } else {
    console.log("\n\nRequesting money from L1");
    // L2 just sent an amount request to L1, receive this message here
    let l2VaultSeq = await l2wormhole.nextSequence(l2WormholeRouterAddr);
    const requestVAA = await utils.getVAA(l2WormholeRouterAddr, String(l2VaultSeq - 1), CHAIN_ID_POLYGON, 64);

    tx = await l1Vault.receiveMessage(requestVAA);
    await tx.wait();
    console.log("Received request from L2 on L1. Transfer from L1 to L2 initiated.");

    // L1 just sent money along with a message to L2
    // Wait for money to hit bridgeEscrow, then use message to clear funds from bridgeEscrow to l2 vault
    await utils.waitForNonZeroAddressTokenBalance(
      await l2Vault.token(),
      usdcABI,
      "L2 BridgeEscrow",
      l2BridgeEscrow.address,
      mumbaiProvider,
    );
    console.log("\n\nBridgeEscrow contract has received funds. Getting transfer VAA from L1 Wormhole Router");
    let l1VaultSeq = await l1wormhole.nextSequence(l1WormholeRouterAddr);
    const transferVAA = await utils.getVAA(l1WormholeRouterAddr, String(l1VaultSeq - 1), CHAIN_ID_ETH);

    console.log("Clearing funds from bridgeEscrow");
    tx = await l2WormholeRouter.receiveFunds(transferVAA);
    await tx.wait();
  }
}

main()
  .then(() => {
    console.log("Rebalancing completed!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
