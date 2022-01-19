import hre from "hardhat";
import { ethers } from "hardhat";

const ETH_NETWORK_NAME = "ethGoerli";
const POLYGON_NETWORK_NAME = "polygonMumbai";

async function deployToken() {
  // deploy MintableToken on Polygon and Ethereum

  // Polygon
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  let [signer] = await ethers.getSigners();
  let tokenFactory = await ethers.getContractFactory("MintableToken", signer);
  let token = await tokenFactory.deploy(ethers.utils.parseUnits("100000", 6));
  await token.deployed();
  console.log("Polygon token: ", token.address);

  // ethereum
  hre.changeNetwork(ETH_NETWORK_NAME);
  [signer] = await ethers.getSigners();
  tokenFactory = await ethers.getContractFactory("MintableToken", signer);

  token = await tokenFactory.deploy(ethers.utils.parseUnits("100000", 6));
  await token.deployed();
  console.log("ETH token: ", token.address);
}

deployToken()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
