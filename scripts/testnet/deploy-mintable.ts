import { TransactionResponse } from "@ethersproject/abstract-provider";
import { IUniLikeSwapRouter__factory, MintableToken__factory } from "../../typechain";
import hre from "hardhat";
import { ethers } from "hardhat";
import { config } from "../../utils/config";
import { getContractAddress } from "../../utils/export";

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

// Deploy Mintable USDC (ran once, don't need to run again)
async function deployToken() {
  // deploy MintableToken on Polygon and Ethereum

  // Polygon
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  let [signer] = await ethers.getSigners();
  let tokenFactory = await ethers.getContractFactory("MintableToken", signer);
  let token = await tokenFactory.deploy("Mintable USDC", "USDC", 6, ethers.utils.parseUnits("100000", 6));
  await token.deployed();
  console.log("Polygon token: ", token.address);

  // ethereum
  hre.changeNetwork(ETH_NETWORK_NAME);
  [signer] = await ethers.getSigners();
  tokenFactory = await ethers.getContractFactory("MintableToken", signer);

  token = await tokenFactory.deploy("Mintable USDC", "USDC", 6, ethers.utils.parseUnits("100000", 6));
  await token.deployed();
  console.log("ETH token: ", token.address);
}

// Mumbai only
// Assume we have already deployed mintable usdc
// Deploy usdc/btc, and usdc/eth pairs
async function deployBtcEth() {
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  const [signer] = await ethers.getSigners();

  // mint some usdc to add to pairs
  const usdc = MintableToken__factory.connect(config.l2USDC, signer);
  await usdc.mint(signer.address, 200e6);

  let tokenFactory = await ethers.getContractFactory("MintableToken", signer);
  const btc = await tokenFactory.deploy("Mintable BTC", "BTC", 18, ethers.utils.parseUnits(String(10_000), 18));
  await btc.deployed();

  const weth = await tokenFactory.deploy("Mintable WETH", "WETH", 18, ethers.utils.parseUnits(String(10_000), 18));
  await weth.deployed();

  const btcAddr = await getContractAddress(btc);
  const ethAddr = await getContractAddress(weth);
  console.log("BTC ", btcAddr);
  console.log("WETH: ", ethAddr);

  // Deploy usdc/btc, and usdc/eth pairs
  const router = IUniLikeSwapRouter__factory.connect("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", signer);

  // Max approvals in order to add liquidity
  let tx = await btc.attach(btcAddr).connect(signer).approve(router.address, ethers.BigNumber.from(2).pow(256).sub(1));
  await tx.wait();
  tx = await weth.attach(ethAddr).connect(signer).approve(router.address, ethers.BigNumber.from(2).pow(256).sub(1));
  await tx.wait();
  tx = await usdc.connect(signer).approve(router.address, ethers.BigNumber.from(2).pow(256).sub(1));
  await tx.wait();

  console.log("approvals done");
}

async function addLiquidity() {
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  let [signer] = await ethers.getSigners();
  const { wbtc: btcAddr, weth: ethAddr } = config;

  const router = IUniLikeSwapRouter__factory.connect("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", signer);
  const usdc = MintableToken__factory.connect(config.l2USDC, signer);
  const btc = MintableToken__factory.connect(btcAddr, signer);
  const eth = MintableToken__factory.connect(ethAddr, signer);

  const oneToken = ethers.BigNumber.from(10).pow(18);
  const oneHunderedMUsdc = ethers.BigNumber.from(100e6).mul(1e6); // 2500 BTC at a price of $40k, 33,333 at price of $3k
  const oneHunderedMBtc = ethers.BigNumber.from(2500).mul(oneToken);
  const oneHundredMEth = ethers.BigNumber.from(33_333).mul(oneToken);

  // Mint some tokens
  let tx = await usdc.mint(signer.address, oneHunderedMUsdc.mul(2));
  await tx.wait();
  tx = await btc.mint(signer.address, oneHunderedMBtc);
  await tx.wait();
  tx = await eth.mint(signer.address, oneHundredMEth);
  await tx.wait;

  // Add liquidity
  const deadline = Math.floor(Date.now() / 1000) + 24 * 60 * 60; // unix timestamp in seconds plus 24 hours

  // usdc/btc
  tx = await router.addLiquidity(
    config.l2USDC,
    btcAddr,
    oneHunderedMUsdc,
    oneHunderedMBtc,
    0,
    0,
    signer.address,
    deadline,
    { gasLimit: 10e6 },
  );
  await tx.wait();

  // usdc/eth
  tx = await router.addLiquidity(
    config.l2USDC,
    ethAddr,
    oneHunderedMUsdc,
    oneHundredMEth,
    0,
    0,
    signer.address,
    deadline,
    { gasLimit: 10e6 },
  );
  await tx.wait();
  console.log("Liquidity added");
}

addLiquidity()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
