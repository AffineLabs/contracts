import { resolve, join } from "path";
import { readJSON, outputJSON } from "fs-extra";
import { Contract } from "ethers";
import { ethers } from "hardhat";

// Wayaround for https://github.com/nomiclabs/hardhat/issues/2162
export async function getContractAddress(contract: Contract): Promise<string> {
  const txHash = contract.deployTransaction.hash;
  const txReceipt = await ethers.provider.waitForTransaction(txHash);
  return txReceipt.contractAddress;
}

export async function addToAddressBook(contractName: string, contract: Contract) {
  const addressBookDir = resolve(__dirname, "..");
  const addressBookPath = join(addressBookDir, "addressbook.json");
  let addressBook;
  try {
    addressBook = await readJSON(addressBookPath);
  } catch (err) {
    addressBook = {};
  }
  addressBook[contractName] = await getContractAddress(contract);
  await outputJSON(addressBookPath, addressBook, { spaces: 2 });
}
