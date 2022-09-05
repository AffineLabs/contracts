import utils from "../test/utils";
import { ethers } from "ethers";

import { BOT_CONFIG } from "./utils/bot-config";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";
import {
  IWormhole__factory,
  L1Vault__factory,
  L1WormholeRouter__factory,
  L2Vault__factory,
  L2WormholeRouter__factory,
} from "../typechain";
import { readAddressBook } from "./utils/export";

const { ethSigner, polygonSigner } = BOT_CONFIG;

async function setup() {
  const addrBook = await readAddressBook("test");
  const l1WormholeRouter = L1WormholeRouter__factory.connect(addrBook.EthWormholeRouter.address, ethSigner);
  const l2WormholeRouter = L2WormholeRouter__factory.connect(addrBook.PolygonWormholeRouter.address, polygonSigner);
  const l1Wormhole = IWormhole__factory.connect(await l1WormholeRouter.wormhole(), ethSigner);
  const l2Wormhole = IWormhole__factory.connect(await l2WormholeRouter.wormhole(), polygonSigner);

  const l1Vault = L1Vault__factory.connect(addrBook.EthAlpSave.address, ethSigner);
  const l2Vault = L2Vault__factory.connect(addrBook.PolygonAlpSave.address, polygonSigner);
  return { l1Vault, l2Vault, l1WormholeRouter, l2WormholeRouter, l1Wormhole, l2Wormhole };
}

async function eventHandler() {
  const { l1Vault, l2Vault, l1WormholeRouter, l2WormholeRouter, l1Wormhole, l2Wormhole } = await setup();
  l1Vault.on("SendTVL", async tvl => {
    console.log("Receiving TVL");
    let l1VaultSeq = await l1Wormhole.nextSequence(l1WormholeRouter.address);
    const tvlVAA = await utils.getVAA(l1WormholeRouter.address, String(l1VaultSeq.sub(1)), CHAIN_ID_ETH);
    console.log("Got VAA");
    const tx = await l2WormholeRouter.receiveTVL(tvlVAA);
    console.log({ tx });
    await tx.wait();
    console.log("receiveTVL complete");
  });
  l1WormholeRouter.on("TransferToL2", async amount => {
    await utils.waitForNonZeroAddressTokenBalance(
      await l2Vault.asset(),
      "L2 BridgeEscrow",
      await l2Vault.bridgeEscrow(),
      ethSigner.provider as ethers.providers.Provider,
    );
    console.log("\n\nBridgeEscrow contract has received funds. Getting transfer VAA from L1 Wormhole Router");
    let l1VaultSeq = await l1Wormhole.nextSequence(l1WormholeRouter.address);
    const transferVAA = await utils.getVAA(l1WormholeRouter.address, String(l1VaultSeq.sub(1)), CHAIN_ID_ETH);

    console.log("Clearing funds from bridgeEscrow");
    const tx = await l2WormholeRouter.receiveFunds(transferVAA);
    await tx.wait();
  });
  l2Vault.on("RequestFromL1", async mount => {
    let l2VaultSeq = await l2Wormhole.nextSequence(l2WormholeRouter.address);
    const requestVAA = await utils.getVAA(l2WormholeRouter.address, String(l2VaultSeq.sub(1)), CHAIN_ID_POLYGON, 64);

    const tx = await l1WormholeRouter.receiveFundRequest(requestVAA);
    await tx.wait();
    console.log("Received request from L2 on L1. Transfer from L1 to L2 initiated.");
  });
  l2Vault.on("TransferToL1", async (amount, event) => {
    console.log("\n\nSending money to L1");
    const messageProof = await utils.waitForL2MessageProof(
      "https://apis.matic.network/api/v1/mumbai",
      event.transactionHash,
      "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", // ERC20 transfer event sig.
    );
    // Get VAA
    let l2VaultSeq = await l2Wormhole.nextSequence(l2WormholeRouter.address);
    const transferVAA = await utils.getVAA(l2WormholeRouter.address, l2VaultSeq.toString(), CHAIN_ID_POLYGON, 64);

    // Post VAA to clear funds
    console.log("Clearing funds from L1 BridgeEscrow");
    const tx = await l1WormholeRouter.receiveFunds(transferVAA, ethers.utils.arrayify(messageProof));
    await tx.wait();
    console.log("Funds cleared from L1 BridgeEscrow");
  });
}

async function sendTVL() {
  const { l1Vault } = await setup();
  l1Vault.sendTVL();
}

async function main() {
  await eventHandler();
  await sendTVL();
}

main();
