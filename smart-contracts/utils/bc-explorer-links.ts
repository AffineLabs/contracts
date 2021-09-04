export function getEthGoerliExplorerLink(txHash: string): string {
    return `https://goerli.etherscan.io/tx/${txHash}`
}

export function getPolygonMumbaiExplorerLink(txHash: string): string {
    return `https://mumbai.polygonscan.com/tx/${txHash}`
}