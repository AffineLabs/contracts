import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";

dotenvConfig({ path: resolve(__dirname, "./.env") });

export interface BotConfig {
  ethNetworkName: string;
  polygonNetworkName: string;
  mnemonic: string;
  contractVersion: string;
  defenderRelayerAPIKey: string;
  defenderRelaterAPISecret: string;
}

const ethNetworkName = process.env.ETH_NETWORK || "eth-goerli-fork";
const polygonNetworkName = process.env.POLYGON_NETWORK || "polygon-mumbai-fork";
const mnemonic = process.env.MNEMONIC || "";
const contractVersion = process.env.CONTRACT_VERSION || "";
const defenderRelayerAPIKey = process.env.DEFENDER_RELAYER_API_KEY || "";
const defenderRelaterAPISecret = process.env.DEFENDER_RELAYER_API_SECRET || "";

export const BOT_CONFIG: BotConfig = {
  ethNetworkName,
  polygonNetworkName,
  mnemonic,
  contractVersion,
  defenderRelayerAPIKey,
  defenderRelaterAPISecret,
};

Object.entries(BOT_CONFIG).map(([key, val]) => {
  if (val === "") throw Error(`${key} may not be empty. Check .env file`);
});
