import { upgrades } from "hardhat";
import hre from "hardhat";
import { config } from "../utils/config";

async function main () {
  hre.changeNetwork('ethGoerli');
  const goerliSafe = config.l1Governance;
  console.log('Transferring ownership of ProxyAdmin in Goerli...');
  // The owner of the ProxyAdmin can upgrade our contracts
  await upgrades.admin.transferProxyAdminOwnership(goerliSafe);
  console.log('Transferred ownership of ProxyAdmin in Goerli to:', goerliSafe);

  hre.changeNetwork('polygonMumbai');
  const mumbaiSafe = config.l2Governance;
  console.log('Transferring ownership of ProxyAdmin in Mumbai...');
  // The owner of the ProxyAdmin can upgrade our contracts
  await upgrades.admin.transferProxyAdminOwnership(mumbaiSafe);
  console.log('Transferred ownership of ProxyAdmin in Mumbai to:', mumbaiSafe);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });