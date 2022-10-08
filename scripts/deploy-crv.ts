import { ethers } from "hardhat";
import hre from "hardhat";
import { readAddressBook } from "./utils/export";

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
// const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

export async function deployCrvStrat() {
  hre.changeNetwork(ETH_NETWORK_NAME);
  const addressBook = await readAddressBook("v1.0-alpha");

  const factory = await ethers.getContractFactory("CurveStrategy");
  const strategy = await factory.deploy(
    addressBook.EthAlpSave.address,
    "0x5a6A4D54456819380173272A5E8E9B9904BdF41B", // MIM-3crv metapool
    "0xA79828DF1850E8a3A3064576f380D90aECDD3359", // 3pool deposit zap
    2, // index representing usdc
    "0xd8b712d29381748dB89c36BCa0138d7c75866ddF", // liquidity gauge
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // uniswap router
    "0xD533a949740bb3306d119CC777fa900bA034cd52", // crv address
  );
  await strategy.deployed();
}

deployCrvStrat()
  .then(() => {
    console.log("Crv strat deployed.");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
