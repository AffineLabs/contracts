import { resolve, join } from "path";
import { readJSON, outputJSON } from "fs-extra";
import { Contract } from "ethers";
import { ethers } from "hardhat";
import { address } from "./types";

// Wayaround for https://github.com/nomiclabs/hardhat/issues/2162
export async function getContractAddress(contract: Contract): Promise<string> {
  const txHash = contract.deployTransaction.hash;
  const txReceipt = await ethers.provider.waitForTransaction(txHash);
  return txReceipt.contractAddress;
}

export async function addToAddressBook(contractName: string, contractOrAddress: Contract | address) {
  const addressBookDir = resolve(__dirname, "..");
  const addressBookPath = join(addressBookDir, "addressbook.json");
  let addressBook;
  try {
    addressBook = await readJSON(addressBookPath);
  } catch (err) {
    addressBook = {};
  }
  const contractAddr =
    typeof contractOrAddress === "string" ? contractOrAddress : await getContractAddress(contractOrAddress);
  addressBook[contractName] = contractAddr;
  await outputJSON(addressBookPath, addressBook, { spaces: 2 });
}
