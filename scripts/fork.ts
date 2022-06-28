import concurrently from "concurrently";
import { program } from "commander";
import { execSync } from "child_process";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "../.env") });

const ALCHEMY_ETH_GOERLI_KEY = process.env.ALCHEMY_ETH_GOERLI_KEY || "";
const ALCHEMY_POLYGON_MUMBAI_KEY = process.env.ALCHEMY_POLYGON_MUMBAI_KEY || "";

function executeScript(script: string, options: { ethereum: string; polygon: string; fork: boolean }, test: boolean) {
  const hhCommand = test ? "yarn hardhat test" : "yarn hardhat run";
  // url info
  const ethNetwork = `eth-${options.ethereum}`;
  const polygonNetwork = `polygon-${options.polygon}`;
  const ethUrl = `https://eth-${options.ethereum}.alchemyapi.io/v2/${ALCHEMY_ETH_GOERLI_KEY}`;
  const polygonUrl = `https://polygon-${options.polygon}.g.alchemy.com/v2/${ALCHEMY_POLYGON_MUMBAI_KEY}`;

  const shouldFork = options.fork;
  if (!shouldFork) {
    execSync(`${hhCommand} ${script}`, {
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
      `${hhCommand} ${script}`,
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
}

program
  .command("script")
  .argument("<script>", "Script to run, e.g. deploy.ts")
  .action((script, options) => {
    console.log({ script });
    console.log({ options });
    executeScript(script, options, false);
  });

program
  .command("test")
  .description("Run the hardhat tests")
  .argument("[testFiles]", "Glob of tests files, e.g. test/deploy.test.ts")
  .action((testFiles, options) => {
    const script = testFiles ? testFiles : "test/*.test.ts";
    executeScript(script, options, true);
  });

program.commands.forEach(cmd => {
  cmd
    .option("--no-fork", "If present, runs script against real networks instead of forking")
    .option("-eth, --ethereum <net>", "The ethereum network", "goerli")
    .option("-p, --polygon <net>", "The polygon network", "mumbai");
});
program.parse();
