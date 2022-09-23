import { ethers } from "hardhat";
import hre from "hardhat";
import { logContractDeploymentInfo } from "../utils/bc-explorer-links";
import { L1WormholeRouter, L2WormholeRouter } from "../../typechain";
import { addToAddressBookAndDefender } from "../utils/export";
import { totalConfig } from "../utils/config";

export interface WormholeRouterContracts {
  l1WormholeRouter: L1WormholeRouter;
  l2WormholeRouter: L2WormholeRouter;
}

export async function deployWormholeRouters(
  config: totalConfig,
  ethNetworkName: string,
  polygonNetworkName: string,
): Promise<WormholeRouterContracts> {
  /**
   * Deploy l1 wormhole router in eth.
   *
   * */
  console.log("about to deploy l1 wormhole router");
  hre.changeNetwork(ethNetworkName);
  const l1WormholeRouterFactory = await ethers.getContractFactory("L1WormholeRouter");
  const l1WormholeRouter = (await l1WormholeRouterFactory.deploy(config.l1.wormhole)) as L1WormholeRouter;
  await l1WormholeRouter.deployed();
  await addToAddressBookAndDefender(
    ethNetworkName,
    "EthWormholeRouter",
    "L1WormholeRouter",
    l1WormholeRouter,
    [],
    false,
  );
  logContractDeploymentInfo(ethNetworkName, "L1WormholeRouter", l1WormholeRouter);

  /**
   * Deploy l2 wormhole router in Polygon.
   *
   * */
  hre.changeNetwork(polygonNetworkName);
  const l2WormholeRouterFactory = await ethers.getContractFactory("L2WormholeRouter");
  const l2WormholeRouter = (await l2WormholeRouterFactory.deploy(config.l2.wormhole)) as L2WormholeRouter;
  await l2WormholeRouter.deployed();
  await addToAddressBookAndDefender(
    polygonNetworkName,
    "PolygonWormholeRouter",
    "L2WormholeRouter",
    l2WormholeRouter,
    [],
    false,
  );
  logContractDeploymentInfo(polygonNetworkName, "L2WormholeRouter", l2WormholeRouter);

  return {
    l1WormholeRouter,
    l2WormholeRouter,
  };
}
