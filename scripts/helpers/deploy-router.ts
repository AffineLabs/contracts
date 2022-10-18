import { ethers } from "hardhat";
import hre from "hardhat";
import { Forwarder, Router } from "../../typechain";
import { addToAddressBookAndDefender } from "../utils/export";

export async function deployRouter(polygonNetworkName: string, forwarder: Forwarder): Promise<Router> {
  hre.changeNetwork(polygonNetworkName);
  const RouterFactory = await ethers.getContractFactory("Router");
  const router = await RouterFactory.deploy("", forwarder.address);
  await router.deployed();
  await addToAddressBookAndDefender(
    process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    "ERC4626Router",
    "Router",
    router,
  );
  return router;
}
