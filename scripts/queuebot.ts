import { Contract, ethers, Wallet } from "ethers";
import { resolve } from "path";
import { readFileSync } from "fs";
import { readAddressBook } from "./utils/export";

import { REBALANCE_CONFIG } from "./utils/config";

const abiDir = resolve(__dirname, "../abi");
const l2VaultABI = JSON.parse(readFileSync(`${abiDir}/L2Vault.json`).toString());
const emergencyWithdrawalQueueABI = JSON.parse(readFileSync(`${abiDir}/EmergencyWithdrawalQueue.json`).toString());

async function main() {
  const { mnemonic, polygonAlchemyURL } = REBALANCE_CONFIG;

  const mumbaiProvider = new ethers.providers.JsonRpcProvider(polygonAlchemyURL);

  const polygonWallet = Wallet.fromMnemonic(mnemonic).connect(mumbaiProvider);

  const addrBook = await readAddressBook();
  const l2Vault = new Contract(addrBook.EthAlpSave.address, l2VaultABI, polygonWallet);
  const emergencyWithdrawalQueue = new Contract(
    await l2Vault.emergencyWithdrawalQueue(),
    emergencyWithdrawalQueueABI,
    polygonWallet,
  );

  while (true) {
    const curQueueSize = await emergencyWithdrawalQueue.size();
    if (!curQueueSize) {
      break;
    }
    try {
      await emergencyWithdrawalQueue.dequeue(Math.min(curQueueSize, 100));
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
