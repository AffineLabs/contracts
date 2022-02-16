import { ethers } from "hardhat";
import { getContractAddress } from "../../utils/export";

async function deployFixtures() {
  // A fake incentives controller, no real one exists on mumbai
  const [deployer] = await ethers.getSigners();
  const dummyFactory = await ethers.getContractFactory("DummyIncentivesController", deployer);
  const dummyIncentives = await dummyFactory.deploy();
  await dummyIncentives.deployed();
  console.log("incentives done: ", await getContractAddress(dummyIncentives));
}

deployFixtures()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
