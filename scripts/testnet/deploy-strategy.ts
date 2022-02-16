import { ethers } from "hardhat";
import scriptUtils from "../utils";
import { config } from "../../utils/config";
import { getContractAddress } from "../../utils/export";

async function deployAAVE(): Promise<any> {
  let [deployer] = await ethers.getSigners();

  // Using address of USDC compatible with AAVE on mumbai
  const myConfig = { ...config };
  myConfig.l2USDC = "0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e";
  const vaultContracts = await scriptUtils.deployVaults(config.l1Governance, config.l2Governance, "ethGoerli", "polygonMumbai", myConfig);

  const stratFactory = await ethers.getContractFactory("L2AAVEStrategy", deployer);

  // Hardcoding mumbai values
  const strategy = await stratFactory.deploy(
    await getContractAddress(vaultContracts.l2Vault), // TODO: can remove once polygon bug is fixed
    "0xE6ef11C967898F9525D550014FDEdCFAB63536B5", // aave adress provider registry
    "0x0a1AB7aea4314477D40907412554d10d30A0503F", // dummy incentives controller TODO: get value from config
    "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff", // sushiswap router on mumbai
    "0x5B67676a984807a212b1c59eBFc9B3568a474F0a", // reward token -> wrapped matic
    "0x5B67676a984807a212b1c59eBFc9B3568a474F0a", // wrapped matic address
  );
  console.log("strategy address: ", await getContractAddress(strategy));
  await strategy.deployed();

  // add strategy to L2 vault
  await vaultContracts.l2Vault.addStrategy(
    await getContractAddress(strategy),
    5000,
    0,
    ethers.utils.parseUnits("1000", 6),
  );
}

deployAAVE()
  .then(() => {
    console.log("Strategy deployment finished");
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
