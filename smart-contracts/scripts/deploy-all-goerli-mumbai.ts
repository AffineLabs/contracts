import { ethers } from "hardhat";
import { config } from "../utils/config";
import { AllContracts, deployAll } from "./utils/deploy-all";


const ETH_NETWORK_NAME = 'ethGoerli'
const POLYGON_NETOWRK_NAME = 'polygonMumbai'

async function deployAllGoerliMumbai(): Promise<AllContracts> {
  const [governance, defender] = await ethers.getSigners()
  return await deployAll(
    governance,
    defender,
    ETH_NETWORK_NAME,
    POLYGON_NETOWRK_NAME,
    config.checkpointManager,
    config.l1ChainManager,
    config.l1USDC,
    config.l1FxTunnel,
    config.l2USDC,
    config.l2ERC20Predicate,
    config.l2FxTunnel,
    config.create2Deployer,
  )
}

deployAllGoerliMumbai()
  .then(() => {
    console.log('All Contracts deployed and initialized!');
    process.exit(0)
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
