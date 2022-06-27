import { program } from "commander";
import { execSync } from "child_process";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "../.env") });

const ALCHEMY_ETH_GOERLI_KEY = process.env.ALCHEMY_ETH_GOERLI_KEY || "";
const ALCHEMY_POLYGON_MUMBAI_KEY = process.env.ALCHEMY_POLYGON_MUMBAI_KEY || "";

const ALCHEMY_ETH_MAINNET_KEY = process.env.ALCHEMY_ETH_MAINNET_KEY || "";
const ALCHEMY_POLYGON_MAINNET_KEY = process.env.ALCHEMY_POLYGON_MAINNET_KEY || "";

const args = {
  eth: {
    goerli: `--match-contract "^L1.*ForkGoerli$" --fork-url https://eth-goerli.alchemyapi.io/v2/${ALCHEMY_ETH_GOERLI_KEY} --fork-block-number 6267635`,
    mainnet: `--match-contract "^L1.*ForkMainnet$" --fork-url https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_ETH_MAINNET_KEY} --fork-block-number 14971385`,
  },
  polygon: {
    mumbai: `--match-contract "^L2.*ForkMumbai$" --fork-url https://polygon-mumbai.g.alchemy.com/v2/${ALCHEMY_POLYGON_MUMBAI_KEY} --fork-block-number 25804436`,
    mainnet: `--match-contract "^L2.*ForkMainnet$" --fork-url https://polygon-mainnet.g.alchemy.com/v2/${ALCHEMY_POLYGON_MAINNET_KEY} --fork-block-number 29555548`,
  },
};

program
  .command("test")
  .description("Run the forge tests")
  .option("--eth-goerli", "If present, run the goerli fork tests")
  .option("--polygon-mumbai", "If present, run the mumbai fork tests")
  .option("--eth-mainnet", "If present, run the eth mainnet fork tests")
  .option("--polygon-mainnet", "If present, run the eth mainnet fork tests")
  .action(options => {
    execSync("forge test --no-match-contract .*Fork", { stdio: "inherit" });

    if (options.ethGoerli) execSync(`forge test ${args.eth.goerli}`, { stdio: "inherit" });
    if (options.ethMainnet) execSync(`forge test ${args.eth.mainnet}`, { stdio: "inherit" });
    if (options.polygonMumbai) execSync(`forge test ${args.polygon.mumbai}`, { stdio: "inherit" });
    if (options.polygonMainnet) execSync(`forge test ${args.polygon.mainnet}`, { stdio: "inherit" });
  });

program
  .command("snapshot")
  .description("Generate/check the current gas snapshots")
  .option("--eth-goerli", "If present, run the goerli fork tests")
  .option("--polygon-mumbai", "If present, run the mumbai fork tests")
  .option("--eth-mainnet", "If present, run the eth mainnet fork tests")
  .option("--polygon-mainnet", "If present, run the eth mainnet fork tests")
  .option("--check", "Check current gas usage against snapshots")
  .action(options => {
    let check = "";
    if (options.check) check = "--check";
    execSync(`forge snapshot --no-match-contract .*Fork --snap snapshots/.gas-snapshot-no-fork ${check}`, {
      stdio: "inherit",
    });

    if (options.ethGoerli)
      execSync(`forge snapshot ${args.eth.goerli} --snap snapshots/.gas-snapshot-fork-eth-goerli ${check}`, {
        stdio: "inherit",
      });
    if (options.ethMainnet)
      execSync(`forge snapshot ${args.eth.mainnet} --snap snapshots/.gas-snapshot-fork-eth-mainnet ${check}`, {
        stdio: "inherit",
      });
    if (options.polygonMumbai)
      execSync(`forge snapshot ${args.polygon.mumbai} --snap snapshots/.gas-snapshot-fork-polygon-mumbai ${check}`, {
        stdio: "inherit",
      });
    if (options.polygonMainnet)
      execSync(`forge snapshot ${args.polygon.mainnet} --snap snapshots/.gas-snapshot-fork-polygon-mainnet ${check}`, {
        stdio: "inherit",
      });
  });

program.parse();
