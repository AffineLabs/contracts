import axios from "axios";
import * as utils from "./utils/wormhole";
import { ethers } from "hardhat";
import { CHAIN_ID_ETH, CHAIN_ID_POLYGON } from "@certusone/wormhole-sdk";
import {
  ERC20,
  ERC20__factory,
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
  L1BridgeEscrow__factory,
  L2BridgeEscrow__factory,
  L1BridgeEscrow,
  L2BridgeEscrow,
} from "../typechain";
import { readAddressBook } from "./utils/export";
import { Signer } from "ethers";

interface Contracts {
  l1Wormhole: IWormhole;
  l2Wormhole: IWormhole;
  l1WormholeRouter: L1WormholeRouter;
  l2WormholeRouter: L2WormholeRouter;
  l1Vault: L1Vault;
  l2Vault: L2Vault;
  l1BridgeEscrow: L1BridgeEscrow;
  l2BridgeEscrow: L2BridgeEscrow;
  l2USDC: ERC20;
}

interface StepStatus {
  success: boolean;
  message: string;
}

interface RebalanceConfig {
  mainnet: boolean;
  contractVersion: string;
  ethSigner: Signer;
  polygonSigner: Signer;
}

const getAllContracts = async (config: RebalanceConfig, l1Vault: L1Vault, l2Vault: L2Vault): Promise<Contracts> => {
  const l1WormholeRouter = L1WormholeRouter__factory.connect(await l1Vault.wormholeRouter(), config.ethSigner);
  const l2WormholeRouter = L2WormholeRouter__factory.connect(await l2Vault.wormholeRouter(), config.polygonSigner);
  const l1Wormhole = IWormhole__factory.connect(await l1WormholeRouter.wormhole(), config.ethSigner);
  const l2Wormhole = IWormhole__factory.connect(await l2WormholeRouter.wormhole(), config.polygonSigner);

  const l1BridgeEscrow = L1BridgeEscrow__factory.connect(await l1Vault.bridgeEscrow(), config.ethSigner);
  const l2BridgeEscrow = L2BridgeEscrow__factory.connect(await l2Vault.bridgeEscrow(), config.polygonSigner);
  const l2USDC = ERC20__factory.connect(await l2Vault.asset(), config.polygonSigner);
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
};

export class Rebalancer {
  config: RebalanceConfig;
  contracts: Contracts;

  polygonAPIUrl: string;
  wormholeAPIUrl: string;

  constructor(config: RebalanceConfig, contracts: Contracts) {
    this.config = config;
    this.contracts = contracts;

    this.polygonAPIUrl = `https://apis.matic.network/api/v1/${config.mainnet ? "matic" : "mumbai"}`;
    this.wormholeAPIUrl = `https://wormhole-v2-${config.mainnet ? "mainnet" : "testnet"}-api.certus.one`;
  }

  public static buildWithAddressBook = async (config: RebalanceConfig): Promise<Rebalancer> => {
    const addrBook = await readAddressBook(config.contractVersion);

    const l1Vault = L1Vault__factory.connect(addrBook.EthAlpSave.address, config.ethSigner);
    const l2Vault = L2Vault__factory.connect(addrBook.PolygonAlpSave.address, config.polygonSigner);

    return new Rebalancer(config, await getAllContracts(config, l1Vault, l2Vault));
  };

  public static buildWithVault = async (
    config: RebalanceConfig,
    l1Vault: L1Vault,
    l2Vault: L2Vault,
  ): Promise<Rebalancer> => {
    const addrBook = await readAddressBook(config.contractVersion);
    return new Rebalancer(config, await getAllContracts(config, l1Vault, l2Vault));
  };

  trySendingTVLFromL1 = async (): Promise<StepStatus> => {
    let canTransferToL1 = await this.contracts.l2Vault.canTransferToL1();
    let canRequestFromL1 = await this.contracts.l2Vault.canRequestFromL1();
    let received = await this.contracts.l1Vault.received();
    const noRebalanceInProgress = (received && !canTransferToL1) || (canTransferToL1 && canRequestFromL1);
    if (!noRebalanceInProgress) {
      return {
        success: false,
        message: "Rebalance in progress, no need to send TVL",
      };
    }
    let l1WormholeRouterSeq = await this.contracts.l1Wormhole.nextSequence(this.contracts.l1WormholeRouter.address);
    let l1WormholeRouterLastSentTVLNonce = l1WormholeRouterSeq.sub(1);
    if (l1WormholeRouterLastSentTVLNonce.gte(await this.contracts.l2WormholeRouter.nextValidNonce())) {
      return {
        success: false,
        message: "Previous TVLs are yet to be received by L2",
      };
    }
    try {
      const sendTVLTransaction = await this.contracts.l1Vault.sendTVL();
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
  };

  tryReceivingTVLInL2 = async (): Promise<StepStatus> => {
    const l1WormholeRouterSeq = await this.contracts.l1Wormhole.nextSequence(this.contracts.l1WormholeRouter.address);
    const l1WormholeRouterLastSentTVLNonce = l1WormholeRouterSeq.sub(1);
    if (l1WormholeRouterLastSentTVLNonce.lt(await this.contracts.l2WormholeRouter.nextValidNonce())) {
      return {
        success: false,
        message: "No L1 TVL to be received",
      };
    }
    const canRequestFromL1 = await this.contracts.l2Vault.canRequestFromL1();
    if (!canRequestFromL1) {
      return {
        success: false,
        message: "L1 -> L2 rebalance happening, TVL is not expected by L2 at the moment",
      };
    }
    const tvlVAA = await utils.attemptGettingVAA(
      this.wormholeAPIUrl,
      this.contracts.l1WormholeRouter.address,
      await this.contracts.l2WormholeRouter.nextValidNonce(),
      CHAIN_ID_ETH,
    );
    if (tvlVAA === undefined) {
      return {
        success: false,
        message: "Receiving TVL from L1 failed as wormhole VAA is not ready",
      };
    }
    try {
      const receiveTVLTransaction = await this.contracts.l2WormholeRouter.receiveTVL(tvlVAA);
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
  };

  getLatestTransferToL1EventTxHash = async (): Promise<string | undefined> => {
    let transferToL1Events = await this.contracts.l2Vault.queryFilter(
      this.contracts.l2Vault.filters.TransferToL1(),
      -10000,
    );
    if (transferToL1Events.length === 0) {
      transferToL1Events = await this.contracts.l2Vault.queryFilter(this.contracts.l2Vault.filters.TransferToL1());
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
  };

  getL2FundTransferMessageProof = async (): Promise<string | undefined> => {
    const ecr20TransferEventSig = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
    const txHash = await this.getLatestTransferToL1EventTxHash();
    try {
      const { data: maticAPIResponse } = await axios.get(
        `${this.polygonAPIUrl}/all-exit-payloads/${txHash}?eventSignature=${ecr20TransferEventSig}`,
      );
      if ("result" in maticAPIResponse) {
        // `result` is an array of all burn proofs. We want the last one since the last token burned is USDC
        // If we simply use the /exit-payload/ endpoint we might get a burn event we don't care about (like burning amUSDC)
        // on a divestment from the polygon aave strategy
        return maticAPIResponse.result.slice(-1)[0];
      }
      return undefined;
    } catch (e) {
      return undefined;
    }
  };

  getL2FundTransferReportMessageVAA = async (): Promise<Uint8Array | undefined> => {
    return utils.attemptGettingVAA(
      this.wormholeAPIUrl,
      this.contracts.l2WormholeRouter.address,
      await this.contracts.l1WormholeRouter.nextValidNonce(),
      CHAIN_ID_POLYGON,
    );
  };

  tryReceivingFundInL1 = async (): Promise<StepStatus> => {
    const canTransferToL1 = await this.contracts.l2Vault.canTransferToL1();
    // Bridge is not locked in L2 -> L1 direction.
    if (canTransferToL1) {
      return {
        success: false,
        message: "No L2 -> L1 rebalance happening",
      };
    }
    const l2WormholeRouterSeq = await this.contracts.l2Wormhole.nextSequence(this.contracts.l2WormholeRouter.address);
    const l2WormholeRouterLastSentFundTransferReportNonce = l2WormholeRouterSeq.sub(1);
    if (l2WormholeRouterLastSentFundTransferReportNonce.lt(await this.contracts.l1WormholeRouter.nextValidNonce())) {
      return {
        success: false,
        message: "No fund to be received in L1",
      };
    }
    const l2FundTransferReportMessageVAA = await this.getL2FundTransferReportMessageVAA();
    const l2FundTransferMessageProof = await this.getL2FundTransferMessageProof();
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
      const clearFundTransaction = await this.contracts.l1WormholeRouter.receiveFunds(
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
  };

  tryTrigerringTransferFromL1 = async (): Promise<StepStatus> => {
    const canRequestFromL1 = await this.contracts.l2Vault.canRequestFromL1();
    // Bridge is not locked in L1 -> L2 direction.
    if (canRequestFromL1) {
      return {
        success: false,
        message: "No L1 -> L2 rebalance happening",
      };
    }
    const l2WormholeRouterSeq = await this.contracts.l2Wormhole.nextSequence(this.contracts.l2WormholeRouter.address);
    const l2WormholeRouterLastSentFundRequestNonce = l2WormholeRouterSeq.sub(1);
    if (l2WormholeRouterLastSentFundRequestNonce.lt(await this.contracts.l1WormholeRouter.nextValidNonce())) {
      return {
        success: false,
        message: "No fund to be requested to L1",
      };
    }
    const l2WormholeRouterLastSentFundRequestVAA = await utils.attemptGettingVAA(
      this.wormholeAPIUrl,
      this.contracts.l2WormholeRouter.address,
      await this.contracts.l1WormholeRouter.nextValidNonce(),
      CHAIN_ID_POLYGON,
    );
    if (l2WormholeRouterLastSentFundRequestVAA === undefined) {
      return {
        success: false,
        message: "L2 fund request VAA not yet available",
      };
    }
    try {
      const fundTransferToL2Transaction = await this.contracts.l1WormholeRouter.receiveFundRequest(
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
  };

  tryClearingFundsFromL2Escrow = async (): Promise<StepStatus> => {
    const canRequestFromL1 = await this.contracts.l2Vault.canRequestFromL1();
    // Bridge is not locked in L1 -> L2 direction.
    if (canRequestFromL1) {
      return {
        success: false,
        message: "No L1 -> L2 rebalance happening",
      };
    }
    const l1WormholeRouterSeq = await this.contracts.l1Wormhole.nextSequence(this.contracts.l1WormholeRouter.address);
    const l1WormholeRouterFundTransferReportNonce = l1WormholeRouterSeq.sub(1);
    if (l1WormholeRouterFundTransferReportNonce.lt(await this.contracts.l2WormholeRouter.nextValidNonce())) {
      return {
        success: false,
        message: "No funds to be cleared in L2",
      };
    }
    const l2BridgeEscrowUSDCBalance = await this.contracts.l2USDC.balanceOf(this.contracts.l2BridgeEscrow.address);
    if (l2BridgeEscrowUSDCBalance.isZero()) {
      return {
        success: false,
        message: "Funds are not received by L2 escrow yet",
      };
    }
    const l1WormholeRouterFundTransferReportVAA = await utils.attemptGettingVAA(
      this.wormholeAPIUrl,
      this.contracts.l1WormholeRouter.address,
      await this.contracts.l2WormholeRouter.nextValidNonce(),
      CHAIN_ID_ETH,
    );
    if (l1WormholeRouterFundTransferReportVAA === undefined) {
      return {
        success: false,
        message: "L1 fund transfer report VAA not yet available",
      };
    }
    try {
      const l1ReceiveFundsTransactions = await this.contracts.l2WormholeRouter.receiveFunds(
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
  };

  run = async () => {
    console.log("Trying to send TVL from L1 to L2:", await this.trySendingTVLFromL1());
    console.log("Trying to receive L1 TVL in L2:", await this.tryReceivingTVLInL2());
    console.log("Trying to receive fund in L1:", await this.tryReceivingFundInL1());
    console.log("Trying to trigger fund transfer from L1 to L2:", await this.tryTrigerringTransferFromL1());
    console.log("Trying to clear funds from L2 escrow:", await this.tryClearingFundsFromL2Escrow());
  };
}
