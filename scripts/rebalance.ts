import axios from "axios";
import { Wallet } from "ethers";
import utils from "../test/utils";
import { ethers, config } from "hardhat";

import { BOT_CONFIG } from "./utils/config";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";
import {
  ERC20,
  ERC20__factory,
  IBridgeEscrow,
  IBridgeEscrow__factory,
  IWormhole,
  IWormhole__factory,
  L1Vault,
  L1Vault__factory,
  L1WormholeRouter,
  L1WormholeRouter__factory,
  L2Vault,
  L2Vault__factory,
  L2WormholeRouter,
  L2WormholeRouter__factory,
} from "../typechain";
import { readAddressBook } from "./utils/export";
import { HttpNetworkConfig } from "hardhat/types";

const { ethNetworkName, polygonNetworkName, mnemonic, contractVersion } = BOT_CONFIG;

interface Contracts {
  l1Wormhole: IWormhole;
  l2Wormhole: IWormhole;
  l1WormholeRouter: L1WormholeRouter;
  l2WormholeRouter: L2WormholeRouter;
  l1Vault: L1Vault;
  l2Vault: L2Vault;
  l1BridgeEscrow: IBridgeEscrow;
  l2BridgeEscrow: IBridgeEscrow;
  l2USDC: ERC20;
}

interface StepStatus {
  success: boolean;
  message: string;
}

function isMainnet() {
  return ethNetworkName === "eth-mainnet" && polygonNetworkName === "polygon-mainnet";
}

function getPolygonAPIURL() {
  return `https://apis.matic.network/api/v1/${isMainnet() ? "matic" : "mumbai"}`;
}

function getWormholeAPIURL() {
  return `https://wormhole-v2-${isMainnet() ? "mainnet" : "testnet"}-api.certus.one`;
}

async function getContracts(): Promise<Contracts> {
  // Read addressbook
  const addrBook = await readAddressBook(contractVersion);
  // Get eth and polygon providers.
  const ethNetworkConfig = config.networks[ethNetworkName] as HttpNetworkConfig;
  const polygonNetworkConfig = config.networks[polygonNetworkName] as HttpNetworkConfig;
  const ethProvider = new ethers.providers.JsonRpcProvider(ethNetworkConfig.url);
  const polygonProvider = new ethers.providers.JsonRpcProvider(polygonNetworkConfig.url);
  // Get wallets
  const ethWallet = Wallet.fromMnemonic(mnemonic).connect(ethProvider);
  const polygonWallet = Wallet.fromMnemonic(mnemonic).connect(polygonProvider);
  // Get Contracts
  const l1WormholeRouter = L1WormholeRouter__factory.connect(addrBook.EthWormholeRouter.address, ethWallet);
  const l2WormholeRouter = L2WormholeRouter__factory.connect(addrBook.PolygonWormholeRouter.address, polygonWallet);
  const l1Wormhole = IWormhole__factory.connect(await l1WormholeRouter.wormhole(), ethWallet);
  const l2Wormhole = IWormhole__factory.connect(await l2WormholeRouter.wormhole(), polygonWallet);
  const l1Vault = L1Vault__factory.connect(addrBook.EthAlpSave.address, ethWallet);
  const l2Vault = L2Vault__factory.connect(addrBook.PolygonAlpSave.address, polygonWallet);
  const l1BridgeEscrow = IBridgeEscrow__factory.connect(await l1Vault.bridgeEscrow(), ethWallet);
  const l2BridgeEscrow = IBridgeEscrow__factory.connect(await l2Vault.bridgeEscrow(), polygonWallet);
  const l2USDC = ERC20__factory.connect(await l2Vault.asset(), polygonWallet);
  return {
    l1Wormhole,
    l2Wormhole,
    l1WormholeRouter,
    l2WormholeRouter,
    l1Vault,
    l2Vault,
    l1BridgeEscrow,
    l2BridgeEscrow,
    l2USDC,
  };
}

async function trySendingTVLFromL1(contracts: Contracts): Promise<StepStatus> {
  let l1WormholeRouterSeq = await contracts.l1Wormhole.nextSequence(contracts.l1WormholeRouter.address);
  let l1WormholeRouterLastSentTVLNonce = l1WormholeRouterSeq.sub(1);
  if (l1WormholeRouterLastSentTVLNonce.gte(await contracts.l2WormholeRouter.nextValidNonce())) {
    return {
      success: false,
      message: "Previous TVLs are yet to be received by L2",
    };
  }
  let canTransferToL1 = await contracts.l2Vault.canTransferToL1();
  let canRequestFromL1 = await contracts.l2Vault.canRequestFromL1();
  if (canTransferToL1 && canRequestFromL1) {
    try {
      const sendTVLTransaction = await contracts.l1Vault.sendTVL();
      await sendTVLTransaction.wait();
      return {
        success: true,
        message: "Sent TVL to L2 from L1",
      };
    } catch (e) {
      return {
        success: false,
        message: `Sending TVL Failed. Error: ${e}`,
      };
    }
  } else {
    return {
      success: false,
      message: "Rebalance in progress, no need to send TVL",
    };
  }
}

async function tryReceivingTVLInL2(contracts: Contracts): Promise<StepStatus> {
  let l1WormholeRouterSeq = await contracts.l1Wormhole.nextSequence(contracts.l1WormholeRouter.address);
  let l1WormholeRouterLastSentTVLNonce = l1WormholeRouterSeq.sub(1);
  if (l1WormholeRouterLastSentTVLNonce.lt(await contracts.l2WormholeRouter.nextValidNonce())) {
    return {
      success: false,
      message: "No L1 TVL to be received",
    };
  }
  const tvlVAA = await utils.attemptGettingVAA(
    getWormholeAPIURL(),
    contracts.l1WormholeRouter.address,
    l1WormholeRouterLastSentTVLNonce,
    CHAIN_ID_ETH,
  );
  if (tvlVAA === undefined) {
    return {
      success: false,
      message: "Receiving TVL from L1 failed as wormhole VAA is not ready",
    };
  }
  try {
    const receiveTVLTransaction = await contracts.l2WormholeRouter.receiveTVL(tvlVAA);
    await receiveTVLTransaction.wait();
    return {
      success: true,
      message: "Received TVL from L1",
    };
  } catch (e) {
    return {
      success: false,
      message: `Receiving TVL from L1 failed. Error: ${e}`,
    };
  }
}

async function getLatestTransferToL1EventTxHash(contracts: Contracts): Promise<string | undefined> {
  let transferToL1Events = await contracts.l2Vault.queryFilter(contracts.l2Vault.filters.TransferToL1(), -10000);
  if (transferToL1Events.length === 0) {
    transferToL1Events = await contracts.l2Vault.queryFilter(contracts.l2Vault.filters.TransferToL1());
  }
  if (transferToL1Events.length === 0) {
    return undefined;
  }
  let latestEvent = transferToL1Events[0];
  for (const e of transferToL1Events) {
    if (latestEvent === undefined || latestEvent.transactionIndex < e.transactionIndex) {
      latestEvent = e;
    }
  }
  return latestEvent.transactionHash;
}

async function getL2FundTransferMessageProof(contracts: Contracts): Promise<string | undefined> {
  const ecr20TransferEventSig = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
  const { data: maticAPIResponse } = await axios.get(
    `${getPolygonAPIURL()}/exit-payload/${await getLatestTransferToL1EventTxHash(
      contracts,
    )}?eventSignature=${ecr20TransferEventSig}`,
  );
  if ("result" in maticAPIResponse) {
    return maticAPIResponse.result;
  }
  return undefined;
}

async function getL2FundTransferReportMessageVAA(contracts: Contracts): Promise<Uint8Array | undefined> {
  let l2WormholeRouterSeq = await contracts.l2Wormhole.nextSequence(contracts.l2WormholeRouter.address);
  return utils.attemptGettingVAA(
    getWormholeAPIURL(),
    contracts.l2WormholeRouter.address,
    l2WormholeRouterSeq.sub(1),
    CHAIN_ID_POLYGON,
  );
}

async function tryReceivingFundInL1(contracts: Contracts): Promise<StepStatus> {
  const canTransferToL1 = await contracts.l2Vault.canTransferToL1();
  // Bridge is not locked in L2 -> L1 direction.
  if (canTransferToL1) {
    return {
      success: false,
      message: "No L2 -> L1 rebalance happening",
    };
  }
  const l2WormholeRouterSeq = await contracts.l2Wormhole.nextSequence(contracts.l2WormholeRouter.address);
  const l2WormholeRouterLastSentFundTransferReportNonce = l2WormholeRouterSeq.sub(1);
  if (l2WormholeRouterLastSentFundTransferReportNonce.lt(await contracts.l1WormholeRouter.nextValidNonce())) {
    return {
      success: false,
      message: "No fund to be received in L1",
    };
  }
  const l2FundTransferReportMessageVAA = await getL2FundTransferReportMessageVAA(contracts);
  const l2FundTransferMessageProof = await getL2FundTransferMessageProof(contracts);
  if (l2FundTransferReportMessageVAA === undefined || l2FundTransferMessageProof === undefined) {
    let messages = [];
    if (l2FundTransferReportMessageVAA === undefined) {
      messages.push("L2 fund transfer report VAA not yet available");
    }
    if (l2FundTransferMessageProof === undefined) {
      messages.push("L2 fund transfer message proof not yet available");
    }
    return {
      success: false,
      message: messages.join(", "),
    };
  }
  try {
    const clearFundTransaction = await contracts.l1WormholeRouter.receiveFunds(
      l2FundTransferReportMessageVAA,
      ethers.utils.arrayify(l2FundTransferMessageProof),
    );
    await clearFundTransaction.wait();
    return {
      success: true,
      message: "L2 fund received in L1",
    };
  } catch (e) {
    return {
      success: false,
      message: `Something went wrong receiving L2 fund in L1. Error: ${e}`,
    };
  }
}

async function tryTrigerringTransferFromL1(contracts: Contracts): Promise<StepStatus> {
  const canRequestFromL1 = await contracts.l2Vault.canRequestFromL1();
  // Bridge is not locked in L1 -> L2 direction.
  if (canRequestFromL1) {
    return {
      success: false,
      message: "No L1 -> L2 rebalance happening",
    };
  }
  const l2WormholeRouterSeq = await contracts.l2Wormhole.nextSequence(contracts.l2WormholeRouter.address);
  const l2WormholeRouterLastSentFundRequestNonce = l2WormholeRouterSeq.sub(1);
  if (l2WormholeRouterLastSentFundRequestNonce.lt(await contracts.l1WormholeRouter.nextValidNonce())) {
    return {
      success: false,
      message: "No fund to be requested to L1",
    };
  }
  const l2WormholeRouterLastSentFundRequestVAA = await utils.attemptGettingVAA(
    getWormholeAPIURL(),
    contracts.l2WormholeRouter.address,
    l2WormholeRouterLastSentFundRequestNonce,
    CHAIN_ID_POLYGON,
  );
  if (l2WormholeRouterLastSentFundRequestVAA === undefined) {
    return {
      success: false,
      message: "L2 fund request VAA not yet available",
    };
  }
  try {
    const fundTransferToL2Transaction = await contracts.l1WormholeRouter.receiveFundRequest(
      l2WormholeRouterLastSentFundRequestVAA,
    );
    await fundTransferToL2Transaction.wait();
    return {
      success: true,
      message: "Fund transfer from L1 to L2 was triggered",
    };
  } catch (e) {
    return {
      success: false,
      message: `Something went wrong triggering fund transfer from L1 to L2. Error: ${e}`,
    };
  }
}

async function tryClearingFundsFromL2Escrow(contracts: Contracts): Promise<StepStatus> {
  const canRequestFromL1 = await contracts.l2Vault.canRequestFromL1();
  // Bridge is not locked in L1 -> L2 direction.
  if (canRequestFromL1) {
    return {
      success: false,
      message: "No L1 -> L2 rebalance happening",
    };
  }
  const l1WormholeRouterSeq = await contracts.l1Wormhole.nextSequence(contracts.l1WormholeRouter.address);
  const l1WormholeRouterFundTransferReportNonce = l1WormholeRouterSeq.sub(1);
  if (l1WormholeRouterFundTransferReportNonce.lt(await contracts.l2WormholeRouter.nextValidNonce())) {
    return {
      success: false,
      message: "No funds to be cleared in L2",
    };
  }
  const l2BridgeEscrowUSDCBalance = await contracts.l2USDC.balanceOf(contracts.l2BridgeEscrow.address);
  if (l2BridgeEscrowUSDCBalance.isZero()) {
    return {
      success: false,
      message: "Funds are not received by L2 escrow yet",
    };
  }
  const l1WormholeRouterFundTransferReportVAA = await utils.attemptGettingVAA(
    getWormholeAPIURL(),
    contracts.l1WormholeRouter.address,
    l1WormholeRouterSeq,
    CHAIN_ID_ETH,
  );
  if (l1WormholeRouterFundTransferReportVAA === undefined) {
    return {
      success: false,
      message: "L1 fund transfer report VAA not yet available",
    };
  }
  try {
    const l1ReceiveFundsTransactions = await contracts.l2WormholeRouter.receiveFunds(
      l1WormholeRouterFundTransferReportVAA,
    );
    await l1ReceiveFundsTransactions.wait();
    return {
      success: true,
      message: "Funds cleared in L2 Escrow",
    };
  } catch (e) {
    return {
      success: false,
      message: `Something went wrong clearing funds from L2 Escrow. Error: ${e}`,
    };
  }
}

async function main() {
  // Setup
  const contracts = await getContracts();

  console.log("Trying to sent TVL from L1 to L2:", await trySendingTVLFromL1(contracts));
  console.log("Trying to receive L1 TVL in L2:", await tryReceivingTVLInL2(contracts));
  console.log("Trying to receive fund in L1:", await tryReceivingFundInL1(contracts));
  console.log("Trying to trigger fund transfer from L1 to L2:", await tryTrigerringTransferFromL1(contracts));
  console.log("Trying clear funds from L2 escrow:", await tryClearingFundsFromL2Escrow(contracts));
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
