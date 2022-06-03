import { program } from "commander";
import { execSync } from "child_process";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
dotenvConfig({ path: resolve(__dirname, "../.env") });

const ALCHEMY_ETH_KEY = process.env.ALCHEMY_ETH_KEY || "";
const ALCHEMY_POLYGON_KEY = process.env.ALCHEMY_POLYGON_KEY || "";
let ethUrl = `https://eth-goerli.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}`;
let polygonUrl = `https://polygon-mumbai.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}`;

let l1Args = `--match-contract "L1.*Fork" --fork-url ${ethUrl} --fork-block-number 6267635`;
let l2Args = `--match-contract "L2.*Fork" --fork-url ${polygonUrl} --fork-block-number 25804436`;

program
  .command("test")
  .description("Run the forge tests")
  .option("--l1", "If present, run the goerli fork tests")
  .option("--l2", "If present, run the mumbai fork tests")
  .action(options => {
    execSync("forge test --no-match-contract .*Fork", { stdio: "inherit" });

    if (options.l1) execSync(`forge test ${l1Args}`, { stdio: "inherit" });
    if (options.l2) execSync(`forge test ${l2Args}`, { stdio: "inherit" });
  });

program
  .command("snapshot")
  .description("Generate/check the current gas snapshots")
  .option("--l1", "If present, run the goerli fork tests")
  .option("--l2", "If present, run the mumbai fork tests")
  .option("--check", "Check current gas usage against snapshots")
  .action(options => {
    let check = "";
    if (options.check) check = "--check";
    execSync(`forge snapshot --no-match-contract .*Fork --snap snapshots/.gas-snapshot-no-fork ${check}`, {
      stdio: "inherit",
    });
    if (options.l1)
      execSync(`forge snapshot ${l1Args} --snap snapshots/.gas-snapshot-fork-eth ${check}`, { stdio: "inherit" });
    if (options.l2)
      execSync(`forge snapshot ${l2Args} --snap snapshots/.gas-snapshot-fork-polygon ${check}`, { stdio: "inherit" });
  });

program.parse();
