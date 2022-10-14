import { program } from "commander";
import { execSync } from "child_process";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "../.env") });

function executeScript(options: { layer1: boolean; mainnet: boolean; broadcast: boolean }) {
  const ALCHEMY_ETH_KEY =
    (options.mainnet ? process.env.ALCHEMY_ETH_MAINNET_KEY : process.env.ALCHEMY_ETH_GOERLI_KEY) || "";
  const ALCHEMY_POLYGON_KEY =
    (options.mainnet ? process.env.ALCHEMY_POLYGON_MAINNET_KEY : process.env.ALCHEMY_POLYGON_MUMBAI_KEY) || "";

  const ethNet = options.mainnet ? "mainnet" : "goerli";
  const polygonNet = options.mainnet ? "mainnet" : "mumbai";

  const rpcUrl = options.layer1
    ? `https://eth-${ethNet}.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}`
    : `https://polygon-${polygonNet}.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}`;

  const contract = options.layer1 ? "L1.s.sol:Deploy" : "L2.s.sol:Deploy";

  const broadcast = options.broadcast ? "--broadcast" : "";

  const scriptCommand = `forge script script/${contract} --rpc-url ${rpcUrl} --ffi -vvv ${broadcast}`;
  execSync(scriptCommand);
}

program
  .option("-l1, --layer1", "Run script on ethereum, otherwise run on polygon")
  .option("-m, --mainnet", "Run script on mainnet version of eth/polygon. Otherwise use goerli/mumbai")
  .option("-b, --broadcast", "Actually broadcast transactions");

program.parse();

const options = program.opts() as { layer1: boolean; mainnet: boolean; broadcast: boolean };
console.log({ options });
executeScript(options);
