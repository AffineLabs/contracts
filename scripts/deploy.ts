import { defender } from "hardhat";
import { ethers } from "hardhat";
import hre from "hardhat";
import minimist from "minimist"

async function main() {
  const args = minimist(process.argv.slice(2));
  // hre.changeNetwork("ethGoerli");
  // const contractProxyAddress = "0xBF41B5Fe202C1308b271C59d8783C6Be4f32199A";
  // const contractImplName = "L1Vault";
  // const newContractImpl = await ethers.getContractFactory(contractImplName);
  // console.log("Preparing proposal...");
  // const proposal = await defender.proposeUpgrade(contractProxyAddress, newContractImpl);
  // console.log("Upgrade proposal created at:", proposal.url);
  console.log(args);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
