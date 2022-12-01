import { BOT_CONFIG } from "./utils/bot-config";
import { Rebalancer } from "./rebalancer";

const { isMainnet, contractVersion, ethSigner, polygonSigner } = BOT_CONFIG;

const main = async () => {
  const rebalanceConfig = {
    mainnet: isMainnet,
    contractVersion,
    ethSigner,
    polygonSigner,
  };
  const rebalancer = await Rebalancer.buildWithAddressBook(rebalanceConfig);
  await rebalancer.run();
};

main()
  .then(() => {
    console.log("Rebalancing completed!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
