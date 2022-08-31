import { defender, ethers, upgrades } from "hardhat";
import hre from "hardhat";

// See https://docs.openzeppelin.com/upgrades-plugins/1.x/api-hardhat-upgrades#defender-propose-upgrade
export async function deployBasketImplementation() {
  // Cannot propose upgrade because current implmentation is not registered (it was deployed via a github action)
  // Consider updating code to original commit of deployment and running `upgrades.forceImport`

  hre.changeNetwork("polygon-mainnet");

  const factory = await ethers.getContractFactory("TwoAssetBasket");
  const res = await factory.deploy();
}

deployBasketImplementation()
  .then(() => {
    console.log("New implementation deployed");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
