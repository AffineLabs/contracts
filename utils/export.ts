import { resolve, join } from "path";
import { readJSON, outputJSON } from "fs-extra";
import { Contract } from "ethers";
import { ethers } from "hardhat";
import { address } from "./types";
import { BlockchainInfo } from "./constants/types";
import defenderClient from "./defender-client";
import { Contract as DefenderContract } from "defender-admin-client";
import { Network as DefenderNetwork } from "defender-base-client";

// Wayaround for https://github.com/nomiclabs/hardhat/issues/2162
export async function getContractAddress(contract: Contract): Promise<string> {
  const txHash = contract.deployTransaction.hash;
  const txReceipt = await ethers.provider.waitForTransaction(txHash);
  return txReceipt.contractAddress;
}

async function addContractToDefender(
  blockchainInfo: BlockchainInfo,
  contractName: string,
  contractAddr: address,
  abi: string,
) {
  let defenderContract: DefenderContract = {
    name: contractName,
    network: blockchainInfo.network.toLowerCase() as DefenderNetwork,
    abi: JSON.stringify(abi),
    address: contractAddr,
  };
  await defenderClient.addContract(defenderContract);
}

export async function addToAddressBookAndDefender(
  blockchainInfo: BlockchainInfo,
  contractName: string,
  contractType: string,
  contractOrAddress: Contract | address,
  events_to_watch: Array<string> = [],
) {
  const contractAddr =
    typeof contractOrAddress === "string" ? contractOrAddress : await getContractAddress(contractOrAddress);
  const rootDir = resolve(__dirname, "..");
  const addressBookPath = join(rootDir, "addressbook.json");
  let addressBook;
  try {
    addressBook = await readJSON(addressBookPath);
  } catch (err) {
    addressBook = {};
  }

  

  const contractABIPath = join(rootDir, "abi", `${contractType}.json`);
  let abi;
  try {
    abi = await readJSON(contractABIPath);
  } catch (err) {
    abi = {};
    console.warn(`Reading contract abi for contract type "${contractType}" failed.`);
  }

  let entry = {
    blockchain: blockchainInfo.name,
    deployment_net: blockchainInfo.network,
    address: contractAddr,
    lastUpdated: new Date().toUTCString(),
    contractType,
    abi,
    events_to_watch,
    proof_format: blockchainInfo.proof_format,
  };

  addressBook[contractName] = entry;

  await outputJSON(addressBookPath, addressBook, { spaces: 2 });
  await addContractToDefender(blockchainInfo, contractName, contractAddr, abi);
}
