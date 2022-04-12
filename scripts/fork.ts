import concurrently from "concurrently";
import { program } from "commander";
import { execSync } from "child_process";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "../.env") });

const ALCHEMY_ETH_KEY = process.env.ALCHEMY_ETH_KEY || "";
const ALCHEMY_POLYGON_KEY = process.env.ALCHEMY_POLYGON_KEY || "";

// Get network names

let ethUrl = "",
  polygonUrl = "",
  hhScript = "",
  ethNetwork = "",
  polygonNetwork = "";
let shouldFork = true;
let hhCommand = "yarn hardhat run";

program
  .argument("<script>", "Script to run, e.g. deploy.ts")
  .option("--no-fork", "If present, runs script against real networks instead of forking")
  .option("-eth, --ethereum <net>", "The ethereum network", "goerli")
  .option("-p, --polygon <net>", "The polygon network", "mumbai")
  .option("-t, --test", "If present runs a hardhat test instead of a script")
  .action((script, options) => {
    hhScript = script;
    console.log({ script });
    console.log({ options });

    ethNetwork = `eth-${options.ethereum}`;
    polygonNetwork = `polygon-${options.polygon}`;
    ethUrl = `https://eth-${options.ethereum}.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}`;
    polygonUrl = `https://polygon-${options.polygon}.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}`;

    shouldFork = options.fork;
    if (options.test) {
      hhCommand = "yarn hardhat test";
    }
  });

program.parse();

// If we shouldn't fork, then just run the script as usual, putting the chosen networks into our
// environment variables
if (!shouldFork) {
  execSync(`${hhCommand} ${hhScript}`, {
    env: { ...process.env, ETH_NETWORK: ethNetwork, POLYGON_NETWORK: polygonNetwork },
    stdio: "inherit",
  });
  process.exit(0);
}

// If we should fork, start up some hardhat nodes
process.env = { ...process.env, ETH_NETWORK: `${ethNetwork}-fork`, POLYGON_NETWORK: `${polygonNetwork}-fork` };
const { result } = concurrently(
  [
    `yarn hardhat node --fork ${ethUrl}`,
    `yarn hardhat node --fork ${polygonUrl} --port 8546`,
    `${hhCommand} ${hhScript}`,
  ],
  { successCondition: "first", killOthers: ["failure", "failure", "success"] },
);

result.then(
  res => {
    console.log("Script finished successfully.");
    process.exit(0);
  },
  err => {
    console.log("Script failed!");
    console.log({ err });
    process.exit(1);
  },
);
