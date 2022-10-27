import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import { DefenderRelaySigner } from "defender-relay-client/lib/ethers";
import { config } from "hardhat";
import { HttpNetworkConfig } from "hardhat/types";
import { ethers, Signer, Wallet } from "ethers";
import { RelayerApiKey } from "defender-relay-client/lib/relayer";

dotenvConfig({ path: resolve(__dirname, "./.env") });

export interface BotConfig {
  isMainnet: boolean;
  contractVersion: string;
  ethSigner: Signer;
  polygonSigner: Signer;
}

const shouldRelay = process.env.SHOULD_RELAY === "1" ? true : false;

const ethNetworkName = process.env.ETH_NETWORK || "eth-goerli-fork";
const polygonNetworkName = process.env.POLYGON_NETWORK || "polygon-mumbai-fork";
const isMainnet = ethNetworkName.includes("mainnet") && polygonNetworkName.includes("mainnet");

const ethNetworkConfig = config.networks[ethNetworkName] as HttpNetworkConfig;
const polygonNetworkConfig = config.networks[polygonNetworkName] as HttpNetworkConfig;
const ethProvider = new ethers.providers.JsonRpcProvider(ethNetworkConfig.url);
const polygonProvider = new ethers.providers.JsonRpcProvider(polygonNetworkConfig.url);

const mnemonic = process.env.MNEMONIC || "";
const ethMnemonicWallet = Wallet.fromMnemonic(mnemonic).connect(ethProvider);
const polygonMnemonicWallet = Wallet.fromMnemonic(mnemonic).connect(polygonProvider);

const contractVersion = process.env.CONTRACT_VERSION || "";
const ethDefenderRelayerCredentials = {
  apiKey:
    (isMainnet ? process.env.ETH_MAINNET_DEFENDER_RELAYER_API_KEY : process.env.GOERLI_DEFENDER_RELAYER_API_KEY) || "",
  apiSecret:
    (isMainnet
      ? process.env.ETH_MAINNET_DEFENDER_RELAYER_API_SECRET
      : process.env.GOERLI_DEFENDER_RELAYER_API_SECRET) || "",
};

const polygonDefenderRelayerCredentials = {
  apiKey:
    (isMainnet ? process.env.POLYGON_MAINNET_DEFENDER_RELAYER_API_KEY : process.env.MUMBAI_DEFENDER_RELAYER_API_KEY) ||
    "",
  apiSecret:
    (isMainnet
      ? process.env.POLYGON_MAINNET_DEFENDER_RELAYER_API_SECRET
      : process.env.MUMBAI_DEFENDER_RELAYER_API_SECRET) || "",
};

const ethDefenderRelaySigner = new DefenderRelaySigner(ethDefenderRelayerCredentials, ethProvider);
const polygonDefenderRelaySigner = new DefenderRelaySigner(polygonDefenderRelayerCredentials, polygonProvider);

const ethSigner = shouldRelay ? ethDefenderRelaySigner : ethMnemonicWallet;
const polygonSigner = shouldRelay ? polygonDefenderRelaySigner : polygonMnemonicWallet;

export const BOT_CONFIG: BotConfig = {
  isMainnet,
  contractVersion,
  ethSigner,
  polygonSigner,
};

Object.entries(BOT_CONFIG).map(([key, val]) => {
  if (val === "") throw Error(`${key} may not be empty. Check .env file`);
});
