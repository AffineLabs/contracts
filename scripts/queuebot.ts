import { ethers, Wallet } from "ethers";
import { readAddressBook } from "./utils/export";
import { L2Vault__factory, L2Vault, EmergencyWithdrawalQueue__factory, EmergencyWithdrawalQueue } from "../typechain";

import { BOT_CONFIG } from "./utils/bot-config";
import { config } from "hardhat";
import { HttpNetworkConfig } from "hardhat/types";

async function main() {
  const { mnemonic, polygonNetworkName } = BOT_CONFIG;

  const polygonNetworkConfig = config.networks[polygonNetworkName] as HttpNetworkConfig;
  const polygonProvider = new ethers.providers.JsonRpcProvider(polygonNetworkConfig.url);
  const polygonWallet = Wallet.fromMnemonic(mnemonic).connect(polygonProvider);

  const addrBook = await readAddressBook();
  const l2Vault: L2Vault = L2Vault__factory.connect(addrBook.EthAlpSave.address, polygonWallet);
  const emergencyWithdrawalQueue: EmergencyWithdrawalQueue = EmergencyWithdrawalQueue__factory.connect(
    await l2Vault.emergencyWithdrawalQueue(),
    polygonWallet,
  );

  while (true) {
    const curQueueSize = await emergencyWithdrawalQueue.size();
    if (!curQueueSize) {
      break;
    }
    try {
      await emergencyWithdrawalQueue.dequeueBatch(curQueueSize.gt(100) ? 100 : curQueueSize);
    } catch (e) {
      console.log(`Dequeue bot failed with:`, e);
      break;
    }
  }
}

main()
  .then(() => {
    console.log("Dequeue session done!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
