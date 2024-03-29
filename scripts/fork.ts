import concurrently from "concurrently";
import { program } from "commander";
import { execSync } from "child_process";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "../.env") });

function executeScript(
  script: string,
  options: { ethereum: string; polygon: string; fork: boolean; relay: boolean },
  test: boolean,
) {
  const ALCHEMY_ETH_KEY =
    options.ethereum === "mainnet"
      ? process.env.ALCHEMY_ETH_MAINNET_KEY || ""
      : process.env.ALCHEMY_ETH_GOERLI_KEY || "";
  const ALCHEMY_POLYGON_KEY =
    options.polygon === "mainnet"
      ? process.env.ALCHEMY_POLYGON_MAINNET_KEY || ""
      : process.env.ALCHEMY_POLYGON_MUMBAI_KEY || "";

  const hhCommand = test ? "yarn hardhat test" : "yarn hardhat run";
  // url info
  const ethNetwork = `eth-${options.ethereum}`;
  const polygonNetwork = `polygon-${options.polygon}`;

  const ethUrl = `https://eth-${options.ethereum}.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}`;
  const polygonUrl = `https://polygon-${options.polygon}.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}`;

  const shouldFork = options.fork;
  if (!shouldFork) {
    if (options.relay) console.log("Will relay transcations via OZ Defender Relayer");
    execSync(`${hhCommand} ${script}`, {
      env: {
        ...process.env,
        ETH_NETWORK: ethNetwork,
        POLYGON_NETWORK: polygonNetwork,
        SHOULD_RELAY: options.relay ? "1" : "0",
      },
      stdio: "inherit",
    });
    process.exit(0);
  }

  if (options.relay) {
    console.log("[Warning] Not relaying in fork mode.");
  }
  // If we should fork, start up some hardhat nodes
  process.env = { ...process.env, ETH_NETWORK: `${ethNetwork}-fork`, POLYGON_NETWORK: `${polygonNetwork}-fork` };
  const { result } = concurrently(
    [`anvil --fork-url ${ethUrl}`, `anvil --fork-url ${polygonUrl} --port 8546`, `${hhCommand} ${script}`],
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
    .option("-p, --polygon <net>", "The polygon network", "mumbai")
    .option("-r, --relay", "Whether to relay transcations via OZ Defender Relayer or not", false);
});
program.parse();
