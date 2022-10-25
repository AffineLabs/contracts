import { ethers } from "hardhat";
import hre from "hardhat";
import { readAddressBook } from "./utils/export";

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";

export async function deploySushiSwapSSLPStrategy() {
  hre.changeNetwork(ETH_NETWORK_NAME);
  const addressBook = await readAddressBook("v1.0-alpha");
  const factory = await ethers.getContractFactory("DeltaNeutralLp");
  await factory.deploy(
    addressBook.EthAlpSave.address,
    5e16, // Slippage tolerance
    1e15, // Long percentage
    "0x52D306e36E3B6B02c153d0266ff0f85d18BCD413", // Aave lending pool address registry
    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // Asset to borrow (WETH)
    "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419", // Chainlink AggregatorV3Interface (ETH/USD)
    "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // Sushiswap router
    "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac", // Sushiswap factory
  );
}

deploySushiSwapSSLPStrategy()
  .then(() => {
    console.log("Sushiswap SSLP Strategy deployed.");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
