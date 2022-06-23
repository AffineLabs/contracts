import { ethers } from "hardhat";
import { Router } from "../../typechain";
import { POLYGON_MUMBAI } from "../utils/constants/blockchain";
import { addToAddressBookAndDefender } from "../utils/export";

export async function deployRouter(): Promise<Router> {
  const [deployer] = await ethers.getSigners();
  const RouterFactory = await ethers.getContractFactory("Router");
  const router = await RouterFactory.deploy(""); //Add more stuff?
  await router.deployed();
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "ERC4626Router", "Router", router); //unsure what tag should be
  return router;
}
