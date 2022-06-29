import { resolve, join } from "path";
import { readJSON, outputJSON } from "fs-extra";
import { Contract } from "ethers";
import { ethers } from "hardhat";
import { address } from "./types";
import { BlockchainInfo } from "./constants/types";
import defenderClient from "./defender-client";
import { Contract as DefenderContract } from "defender-admin-client";
import { Network as DefenderNetwork } from "defender-base-client";
import axios from "axios";

// Wayaround for https://github.com/nomiclabs/hardhat/issues/2162
export async function getContractAddress(contract: Contract): Promise<string> {
  const txHash = contract.deployTransaction.hash;
  const txReceipt = await ethers.provider.waitForTransaction(txHash);
  return txReceipt.contractAddress;
}

async function addContractToDefender(
  blockchainInfo: BlockchainInfo,
  contractTicker: string,
  contractAddr: address,
  abi: string,
  version: string,
) {
  if (version === "test") return;
  let defenderContract: DefenderContract = {
    name: `${contractTicker} - ${version}.\n Deployed at: ${new Date().toUTCString()}`,
    network: blockchainInfo.network.toLowerCase() as DefenderNetwork,
    abi: JSON.stringify(abi),
    address: contractAddr,
  };
  await defenderClient.addContract(defenderContract);
}

export async function addToAddressBookAndDefender(
  blockchainInfo: BlockchainInfo,
  contractTicker: string,
  contractType: string,
  contractOrAddress: Contract | address,
  events_to_watch: Array<string> = [],
  addToDefender = true,
) {
  const contractAddr =
    typeof contractOrAddress === "string" ? contractOrAddress : await getContractAddress(contractOrAddress);
  const rootDir = resolve(__dirname, "../..");
  const addressBookPath = join(rootDir, "addressbook.json");
  let addressBook;
  try {
    addressBook = await readJSON(addressBookPath);
  } catch (err) {
    addressBook = {};
  }

  const contractABIPath = join(rootDir, "abi", `${contractType}.json`);
  const abi = await readJSON(contractABIPath);

  const version: string = process.env.VERSION || "test";

  let entry = {
    blockchain: blockchainInfo.name,
    deployment_net: blockchainInfo.network,
    network_id: blockchainInfo.network_id,
    address: contractAddr,
    lastUpdated: new Date().toUTCString(),
    contractType,
    abi,
    events_to_watch,
    proof_format: blockchainInfo.proof_format,
    version: version,
  };

  addressBook[contractTicker] = entry;
  await outputJSON(addressBookPath, addressBook, { spaces: 2 });

  if (addToDefender) return addContractToDefender(blockchainInfo, contractTicker, contractAddr, abi, version);
}

export async function readAddressBook(contractVersion: string = "stable") {
  const { data: addressBook } = await axios.get(
    `https://sc-abis.s3.us-east-2.amazonaws.com/${contractVersion}/addressbook.json`,
  );
  return addressBook;
}
