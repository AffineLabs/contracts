import { ethers } from "hardhat";
import { Contract, ContractFactory } from "ethers";

import hre from "hardhat";

const isTestnet = hre.network.config.chainId === 80001;

async function main() {
  const [governance] = await ethers.getSigners();

  console.log("Deploying contracts with the accounts:", [governance.address]);

  const usdcAddress = isTestnet
    ? "0xb31f8a4772ACa8f154bF7aCB0FB9730e973B914a"
    : "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
  console.log("Using usdc: ", usdcAddress);

  // Vault deployed by governance
  const vaultFactory = await ethers.getContractFactory("L2Vault", governance);
  const vault = await vaultFactory.deploy(governance.address, usdcAddress, 1, 1);
  await vault.deployTransaction.wait();
  console.log("vault: ", vault.address);
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
