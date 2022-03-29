import { config } from "../utils/config";
import { AllContracts, deployAll } from "./utils/deploy-all";

async function deployAllGoerliMumbai(): Promise<AllContracts> {
  console.log("eth: ", process.env.ETH_NETWORK);
  console.log("polygon: ", process.env.POLYGON_NETWORK);
  return deployAll(
    config.l1Governance,
    config.l2Governance,
    process.env.ETH_NETWORK || "eth-goerli-fork",
    process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    config,
  );
}

deployAllGoerliMumbai()
  .then(() => {
    console.log("All Contracts deployed and initialized!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
