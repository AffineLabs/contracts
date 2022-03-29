import hre from "hardhat";
import { ethers } from "hardhat";

import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

async function deployCreate2(): Promise<any> {
  hre.changeNetwork(ETH_NETWORK_NAME);
  let [governanceSigner] = await ethers.getSigners();
  let wallet = ethers.Wallet.createRandom().connect(ethers.provider);
  console.log("deployer mnemonic: ", wallet.mnemonic);

  let fundTx = await governanceSigner.sendTransaction({
    to: wallet.address,
    value: ethers.utils.parseEther("0.002"),
  });
  await fundTx.wait();

  // Passing the signer to getContractFactory doesn't work in current vversion of hardhat (2.7.0)
  // So we need to call connect() before deploying
  let create2Factory = await ethers.getContractFactory("Create2Deployer", wallet);
  let create2 = await create2Factory.connect(wallet).deploy();
  await create2.deployed();
  console.log("eth create2: ", await create2.address);

  hre.changeNetwork(POLYGON_NETWORK_NAME);
  [governanceSigner] = await ethers.getSigners();
  wallet = wallet.connect(ethers.provider);

  fundTx = await governanceSigner.sendTransaction({
    to: wallet.address,
    value: ethers.utils.parseEther("0.02"),
  });
  await fundTx.wait();

  create2Factory = await ethers.getContractFactory("Create2Deployer", wallet);
  create2 = await create2Factory.connect(wallet).deploy();
  await create2.deployed();
  console.log("polygon create2: ", await create2.address);
}

deployCreate2()
  .then(() => {
    console.log("Create2 deployment finsished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
