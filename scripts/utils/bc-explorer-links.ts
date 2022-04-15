import { Contract, ContractTransaction } from "ethers";

const NETWORK_TO_EXPLORER_URL = new Map([
  ["eth-mainnet", "mainnet.etherscan.io"],
  ["eth-goerli", "goerli.etherscan.io"],
  ["eth-kovan", "kovan.etherscan.io"],
  ["eth-rinkeby", "rinkeby.etherscan.io"],
  ["eth-ropsten", "ropsten.etherscan.io"],
  ["polygon-mainnet", "mainnet.polygonscan.com"],
  ["polygon-mumbai", "mumbai.polygonscan.com"],
]);

export function logContractDeploymentInfo(networkName: string, contractName: string, contract: Contract) {
  console.log(
    `${contractName} is deployed at address: ${contract.address}\n`,
    `> Explorer URL for Contract: https://${NETWORK_TO_EXPLORER_URL.get(networkName)}/address/${contract.address}\n`,
    contract.deployTransaction
      ? `> Explorer URL for Deployment Tx: https://${NETWORK_TO_EXPLORER_URL.get(networkName)}/tx/${
          contract.deployTransaction.hash
        }\n`
      : "",
  );
}

export function getTxExplorerLink(networkName: string, tx: ContractTransaction) {
  return `https://${NETWORK_TO_EXPLORER_URL.get(networkName)}/tx/${tx.hash}\n`;
}
