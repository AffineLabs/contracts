import { mainnetConfig } from "./utils/config";
import { AllContracts, deployAll } from "./helpers/deploy-all";

async function deployAllMainnet(): Promise<AllContracts> {
  console.log("eth: ", process.env.ETH_NETWORK);
  console.log("polygon: ", process.env.POLYGON_NETWORK);
  return deployAll(
    mainnetConfig.l1.governance,
    mainnetConfig.l2.governance,
    process.env.ETH_NETWORK || "eth-goerli-fork",
    process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    mainnetConfig,
  );
}

deployAllMainnet()
  .then(() => {
    console.log("All Contracts deployed and initialized!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
