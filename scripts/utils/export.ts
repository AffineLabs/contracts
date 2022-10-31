import { resolve, join } from "path";
import { readJSON, outputJSON } from "fs-extra";
import { Contract } from "ethers";
import { address } from "./types";
import { BlockchainInfo, ethChainIds, polygonChainIds } from "./constants/types";
import defenderClient from "./defender-client";
import { Contract as DefenderContract } from "defender-admin-client";
import { Network as DefenderNetwork } from "defender-base-client";
import axios from "axios";
import { ETH_GOERLI, ETH_MAINNET, POLYGON_MAINNET, POLYGON_MUMBAI } from "./constants/blockchain";

async function addContractToDefender(
  blockchainInfo: BlockchainInfo,
  contractTicker: string,
  contractAddr: address,
  abi: string,
  version: string,
) {
  if (version === "test") return;
  let defenderContract: DefenderContract = {
    name: `${contractTicker} - ${version}.`,
    network: blockchainInfo.network.toLowerCase() as DefenderNetwork,
    abi: JSON.stringify(abi),
    address: contractAddr,
  };
  await defenderClient.addContract(defenderContract);
}

export async function addToAddressBookAndDefender(
  networkName: string, // name of the hardhat network we deployed on
  contractTicker: string,
  contractType: string,
  contractOrAddress: Contract | address,
  events_to_watch: Array<string> = [],
  addToDefender = true,
) {
  let blockchainInfo: BlockchainInfo;

  // find blockchainInfo
  if (networkName.includes("mainnet")) {
    if (networkName.includes("eth")) blockchainInfo = ETH_MAINNET;
    else blockchainInfo = POLYGON_MAINNET;
  } else {
    if (networkName.includes("eth")) blockchainInfo = ETH_GOERLI;
    else blockchainInfo = POLYGON_MUMBAI;
  }

  const contractAddr = typeof contractOrAddress === "string" ? contractOrAddress : contractOrAddress.address;
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

interface Transaction {
  transactionType: string;
  contractAddress: string;
  additionalContracts: [{ transactionType: string; address: string }];
}

// Add all deployed contracts to defender and the addressbook after a foundry deployment
export async function defenderEth(forking: boolean, testnet: boolean) {
  return _ethDefender(forking, testnet);
}
export async function defenderPolygon(forking: boolean, testnet: boolean) {
  return _polygonDefender(forking, testnet);
}

async function _ethDefender(forking: boolean, testnet: boolean) {
  // Load the l1 contracts
  const brodcastDir = resolve(__dirname, "../../broadcast");
  const ethChainId = testnet ? ethChainIds.goerli : ethChainIds.mainnet;
  const ethNetwork = testnet ? "eth-testnet" : "eth-mainnet";
  // NOTE: When doing a dryrun, the individual run files are found under the "dry-run" directory
  // e.g. "broadcast/L1.s.sol/1/dry-run/run-$runId.json" vs "broadcast/L1.s.sol/1/dry-run/run-$runId.json" for a real deployment
  const lastestL1DeployPath = join(
    brodcastDir,
    `L1.s.sol/${ethChainId}/`,
    forking ? "dry-run/" : "",
    "run-latest.json",
  );
  console.log({ lastestL1DeployPath });

  // There are four txs. The implementation, the proxy, the escrow, and the router
  const deployData = await readJSON(lastestL1DeployPath);
  const txs: Array<Transaction> = deployData.transactions;
  const l1VaultAddr = txs[1].contractAddress;
  // In this create3Deployer.deploy() tx, we call create2 to create the small proxy and then call create (via the proxy)
  // to create the actual contract
  const escrowAddr = txs[2].additionalContracts.filter(c => c.transactionType === "CREATE")[0].address;
  const routerAddr = txs[3].additionalContracts.filter(c => c.transactionType === "CREATE")[0].address;
  const compAddr = txs[4].contractAddress;
  const curveAddr = txs[5].contractAddress;
  const cvxAddr = txs[6].contractAddress;
  console.log({ l1VaultAddr, escrowAddr, routerAddr });
  await addToAddressBookAndDefender(ethNetwork, "EthAlpSave", "L1Vault", l1VaultAddr);
  await addToAddressBookAndDefender(ethNetwork, "EthWormholeRouter", "L1WormholeRouter", routerAddr, [], false);
  await addToAddressBookAndDefender(ethNetwork, "L1CompoundStrategy", "L1CompoundStrategy", compAddr, [], false);
  await addToAddressBookAndDefender(ethNetwork, "CurveStrategy", "CurveStrategy", curveAddr, [], false);
  await addToAddressBookAndDefender(ethNetwork, "ConvexStrategy", "ConvexStrategy", cvxAddr, [], false);
}

async function _polygonDefender(forking: boolean, testnet: boolean) {
  const brodcastDir = resolve(__dirname, "../../broadcast");
  const polygonChainId = testnet ? polygonChainIds.mumbai : polygonChainIds.mainnet;
  const network = testnet ? "polygon-testnet" : "polygon-mainnet";

  const lastestL2DeployPath = join(
    brodcastDir,
    `L2.s.sol/${polygonChainId}/`,
    forking ? "dry-run/" : "",
    "run-latest.json",
  );
  console.log({ lastestL2DeployPath });

  // Txs:  The forwarder, implementation, the proxy, the escrow, router, ewq, 4626Router,
  // TwoAssetBasket impl, TwoAssetBasket proxy,
  const deployData = await readJSON(lastestL2DeployPath);
  const txs: Array<Transaction> = deployData.transactions;
  const l2VaultAddr = txs[2].contractAddress;
  // In this create3Deployer.deploy() tx, we call create2 to create the small proxy and then call create (via the proxy)
  // to create the actual contract
  const escrowAddr = txs[3].additionalContracts.filter(c => c.transactionType === "CREATE")[0].address;
  const routerAddr = txs[4].additionalContracts.filter(c => c.transactionType === "CREATE")[0].address;
  const ewqAddr = txs[5].additionalContracts.filter(c => c.transactionType === "CREATE")[0].address;
  const router4626Addr = txs[6].contractAddress;
  const basketAddr = txs[8].contractAddress;
  const aaveStratAddr = txs[9].contractAddress;
  console.log({ l2VaultAddr, escrowAddr, routerAddr, ewqAddr, router4626Addr, aaveStratAddr });
  await addToAddressBookAndDefender(network, "PolygonAlpSave", "L2Vault", l2VaultAddr);
  await addToAddressBookAndDefender(network, "PolygonWormholeRouter", "L2WormholeRouter", routerAddr, [], false);
  await addToAddressBookAndDefender(network, "ERC4626Router", "Router", router4626Addr, [], false);
  await addToAddressBookAndDefender(network, "PolygonBtcEthVault", "TwoAssetBasket", basketAddr);
  await addToAddressBookAndDefender(network, "PolygonAAVEStrategy", "L2AAVEStrategy", aaveStratAddr, [], false);
}

export async function readAddressBook(contractVersion: string = "stable") {
  const { data: addressBook } = await axios.get(
    `https://sc-abis.s3.us-east-2.amazonaws.com/${contractVersion}/addressbook.json`,
  );
  return addressBook;
}
