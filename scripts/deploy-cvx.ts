import { ethers } from "hardhat";
import hre from "hardhat";
import { readAddressBook } from "./utils/export";

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

export async function deployCvxStrat() {
  hre.changeNetwork(ETH_NETWORK_NAME);
  const addressBook = await readAddressBook("v1.0-alpha");

  const factory = await ethers.getContractFactory("ConvexStrategy");
  const strategy = await factory.deploy(
    addressBook.EthAlpSave.address,
    "0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2", // frax-usdc curve pool
    100, // convex id for the vurve pool
    "0xF403C135812408BFbE8713b5A23a04b3D48AAE31", // booster
    "0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B", // cvx
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // uniswap router
  );
  await strategy.deployed();
}

deployCvxStrat()
  .then(() => {
    console.log("Cvx strat deployed.");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
