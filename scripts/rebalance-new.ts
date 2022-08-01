import { TransactionResponse } from "@ethersproject/providers";
import { Contract, Wallet } from "ethers";
import utils from "../test/utils";
import { resolve } from "path";
import { readFileSync } from "fs";
import { ethers } from "hardhat";

import { REBALANCE_CONFIG } from "./utils/config";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";
import { L1Vault__factory, L1WormholeRouter__factory, L2Vault__factory, L2WormholeRouter__factory } from "typechain";
import { readAddressBook } from "./utils/export";
import { state_address } from "@certusone/wormhole-sdk/lib/cjs/solana/core/bridge_bg";

const {
  l1WormholeRouterAddr,
  l2WormholeRouterAddr,
  l1VaultAddr,
  l2VaultAddr,
  mnemonic,
  ethAlchemyURL,
  polygonAlchemyURL,
} = REBALANCE_CONFIG;

type state = "Initialization" | "SendMoney" | "ReceiveTVL" | "GetVAA" | "PostVAA" | "L2toL1" | "L1toL2";

const addrBook = await readAddressBook();

const goerliProvider = new ethers.providers.JsonRpcProvider(ethAlchemyURL);
const mumbaiProvider = new ethers.providers.JsonRpcProvider(polygonAlchemyURL);

const ethWallet = Wallet.fromMnemonic(mnemonic).connect(goerliProvider);
const polygonWallet = Wallet.fromMnemonic(mnemonic).connect(mumbaiProvider);
const [signer] = await ethers.getSigners();

console.log("Rebalancer address:", ethWallet.address);

const l1vault = L1Vault__factory.connect(addrBook.EthAlpSave.address, signer);
const l2vault = L2Vault__factory.connect(addrBook.PolygonAlpSave.address, signer);
const l1wormhole = l1vault.wormhole();
const l2wormhole = l2vault.wormhole();
const l1WormholeRouter = L1WormholeRouter__factory.connect(addrBook.EthWormholeRouter.address, signer);
const l2WormholeRouter = L2WormholeRouter__factory.connect(addrBook.PolygonWormholeRouter.address, signer);
const l2BridgeEscrow = l2vault.bridgeEscrow();

async function getState(): Promise<state> {
  if ((await l2vault.canRequestFromL1()) == true) {
    return "Initialization";
  }
  return "ReceiveTVL";
}

async function main() {}

async function rebalance() {}
