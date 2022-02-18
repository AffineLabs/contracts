import { defender } from "hardhat";
import { ethers } from "hardhat";
import hre from "hardhat";

async function main() {
  hre.changeNetwork("ethGoerli");
  const contractProxyAddress = "0x9bc0bcDE1104b9143Dfb3512bDF66e69BA7Ac96E";
  const contractImplName = "L1Vault";
  const newContractImpl = await ethers.getContractFactory(contractImplName);
  console.log("Preparing proposal...");
  const proposal = await defender.proposeUpgrade(contractProxyAddress, newContractImpl);
  console.log("Upgrade proposal created at:", proposal.url);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
