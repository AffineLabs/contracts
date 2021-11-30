import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";

import hre from "hardhat";

const isTestnet = hre.network.config.chainId !== 1;

async function main() {
  const [governance] = await ethers.getSigners();

  console.log("Deploying contracts with the accounts:", [governance.address]);

  const usdcAddress = isTestnet
    ? "0x78dEca24CBa286C0f8d56370f5406B48cFCE2f86"
    : "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  console.log("Using usdc: ", usdcAddress);

  // Vault deployed by governance
  const vaultFactory = await ethers.getContractFactory("L1Vault", governance);
  const vault = await vaultFactory.deploy(governance.address, usdcAddress);
  await vault.deployTransaction.wait();
  console.log("vault: ", vault.address);
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
