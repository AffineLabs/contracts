import { ethers } from "hardhat";
import hre from "hardhat";
import { Forwarder, Router } from "../../typechain";
import { POLYGON_MUMBAI } from "../utils/constants/blockchain";
import { addToAddressBookAndDefender, getContractAddress } from "../utils/export";

export async function deployRouter(polygonNetworkName: string, forwarder: Forwarder): Promise<Router> {
  hre.changeNetwork(polygonNetworkName);
  const [deployer] = await ethers.getSigners();
  const RouterFactory = await ethers.getContractFactory("Router");
  const router = await RouterFactory.deploy("", await getContractAddress(forwarder));
  await router.deployed();
  await addToAddressBookAndDefender(POLYGON_MUMBAI, "ERC4626Router", "Router", router);
  return router;
}
