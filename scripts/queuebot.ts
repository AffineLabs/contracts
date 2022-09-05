import { readAddressBook } from "./utils/export";
import { L2Vault__factory, L2Vault, EmergencyWithdrawalQueue__factory, EmergencyWithdrawalQueue } from "../typechain";

import { BOT_CONFIG } from "./utils/bot-config";

async function main() {
  const { contractVersion, polygonSigner } = BOT_CONFIG;

  const addrBook = await readAddressBook(contractVersion);
  const l2Vault: L2Vault = L2Vault__factory.connect(addrBook.PolygonAlpSave.address, polygonSigner);
  const emergencyWithdrawalQueue: EmergencyWithdrawalQueue = EmergencyWithdrawalQueue__factory.connect(
    await l2Vault.emergencyWithdrawalQueue(),
    polygonSigner,
  );

  while (true) {
    const curQueueSize = await emergencyWithdrawalQueue.size();
    if (curQueueSize.isZero()) {
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
