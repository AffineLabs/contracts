import { Context, ScheduledEvent } from "aws-lambda";
import { ethers } from "ethers";
import { DefenderRelaySigner } from "defender-relay-client/lib/ethers";
import { Rebalancer } from "./rebalancer";

const ethProvider = new ethers.providers.JsonRpcProvider(process.env.ALCHEMY_ETH_URL || "");
const polygonProvider = new ethers.providers.JsonRpcProvider(process.env.ALCHEMY_POLYGON_URL || "");
const ethDefenderRelaySigner = new DefenderRelaySigner(
  {
    apiKey: process.env.ETH_DEFENDER_RELAYER_API_KEY || "",
    apiSecret: process.env.ETH_DEFENDER_RELAYER_API_SECRET || "",
  },
  ethProvider,
);
const polygonDefenderRelaySigner = new DefenderRelaySigner(
  {
    apiKey: process.env.POLYGON_DEFENDER_RELAYER_API_KEY || "",
    apiSecret: process.env.POLYGON_DEFENDER_RELAYER_API_SECRET || "",
  },
  polygonProvider,
);

const rebalanceConfig = {
  mainnet: true,
  contractVersion: process.env.CONTRACT_VERSION || "",
  ethSigner: ethDefenderRelaySigner,
  polygonSigner: polygonDefenderRelaySigner,
};

export const run = async (event: ScheduledEvent, context: Context) => {
  const time = new Date();
  console.log(`Your cron function "${context.functionName}" ran at ${time}`);
  const rebalancer = await Rebalancer.buildWithAddressBook(rebalanceConfig);
  await rebalancer.run();
};
