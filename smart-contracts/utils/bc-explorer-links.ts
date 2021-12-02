import { Contract, ContractTransaction } from "ethers"

const NETWORK_TO_EXPLORER_URL = new Map([
    ["ethMainnet", "mainnet.etherscan.io"],
    ["ethGoerli", "goerli.etherscan.io"],
    ["ethKovan", "kovan.etherscan.io"],
    ["ethRinkeby", "rinkeby.etherscan.io"],
    ["ethRopsten", "ropsten.etherscan.io"],
    ["polygonMainnet", "mainnet.polygonscan.com"],
    ["polygonMumbai", "mumbai.polygonscan.com"],
])

export function logContractDeploymentInfo(networkName: string, contractName: string, contract: Contract) {
    console.log(
        `${contractName} is deployed at address: ${contract.address}\n`, 
        `> Explorer URL for Contract: https://${NETWORK_TO_EXPLORER_URL.get(networkName)}/address/${contract.address}\n`,
        `> Explorer URL for Deployment Tx: https://${NETWORK_TO_EXPLORER_URL.get(networkName)}/tx/${contract.deployTransaction.hash}\n`,
    )
}

export function getTxExplorerLink(networkName: string, tx: ContractTransaction) {
    return `https://${NETWORK_TO_EXPLORER_URL.get(networkName)}/tx/${tx.hash}\n`
}