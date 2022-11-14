import { program } from "commander";
import { execSync } from "child_process";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "../.env") });
import { defenderEth, defenderPolygon } from "./utils/export";

function executeScript(options: { layer: "1" | "2"; testnet: boolean; broadcast: boolean }) {
  const isTest = options.testnet;
  const isLayer1 = options.layer === "1";
  if (options.layer !== "1" && options.layer !== "2") throw Error("Invalid layer");

  const ALCHEMY_ETH_KEY = (isTest ? process.env.ALCHEMY_ETH_GOERLI_KEY : process.env.ALCHEMY_ETH_MAINNET_KEY) || "";
  const ALCHEMY_POLYGON_KEY =
    (isTest ? process.env.ALCHEMY_POLYGON_MUMBAI_KEY : process.env.ALCHEMY_POLYGON_MAINNET_KEY) || "";

  const ethNet = isTest ? "goerli" : "mainnet";
  const polygonNet = isTest ? "mumbai" : "mainnet";

  const rpcUrl = isLayer1
    ? `https://eth-${ethNet}.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}`
    : `https://polygon-${polygonNet}.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}`;

  const contract = isLayer1 ? "L1.s.sol:Deploy" : "L2.s.sol:Deploy";
  const broadcast = options.broadcast ? "--broadcast" : "";
  const testEnv = isTest ? "true" : "false";

  const scriptCommand = `TEST=${testEnv} forge script script/${contract} --rpc-url ${rpcUrl} --ffi -vvv ${broadcast}`;
  execSync(scriptCommand, { stdio: "inherit" });
  if (isLayer1) defenderEth(!options.broadcast, isTest);
  else defenderPolygon(!options.broadcast, isTest);
}

program
  .requiredOption("-l, --layer <layer>", "The layer to run the script on. Use 1 for eth and 2 for polygon")
  .option("-t, --testnet", "Run script on goerli/mumbai instead of eth/polygon")
  .option("-b, --broadcast", "Actually broadcast transactions");

program.parse();

const options = program.opts() as { layer: "1" | "2"; testnet: boolean; broadcast: boolean };
console.log({ options });
executeScript(options);
