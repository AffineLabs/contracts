import { ethers } from "hardhat";
import hre from "hardhat";

async function deployNewL1Vault() {
  hre.changeNetwork("eth-mainnet");
  const [ethDeployerSigner] = await ethers.getSigners();
  console.log("Deployer", ethDeployerSigner.address);
  const ethAlpSaveImplFactory = await ethers.getContractFactory("L1Vault");
  console.log("[Eth] Deploy Alp Save");
  const ethAlpSaveImpl = await ethAlpSaveImplFactory.deploy();

  console.log("Eth Alp Save Impl:", ethAlpSaveImpl.address);
}

deployNewL1Vault()
  .then(() => {
    console.log("Path completed!");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
