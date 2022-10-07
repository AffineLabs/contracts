import { ethers } from "hardhat";
import hre from "hardhat";
import { readAddressBook } from "./utils/export";

const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

export async function deploySushiSwapSSLPStrategy() {
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  const addressBook = await readAddressBook("v1.0-alpha");
  const factory = await ethers.getContractFactory("DeltaNeutralLp");
  await factory.deploy(
    addressBook.PolygonAlpSave.address,
    5e16, // Slippage tolerance
    1e15, // Long percentage
    "0x3ac4e9aa29940770aeC38fe853a4bbabb2dA9C19", // Aave lending pool address registry
    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // Asset to borrow
    "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0", // Chainlink AggregatorV3Interface
    "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // Sushiswap router
    "0xc35DADB65012eC5796536bD9864eD8773aBc74C4", // Sushiswap factory
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
