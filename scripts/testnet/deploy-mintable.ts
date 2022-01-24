import { TransactionResponse } from "@ethersproject/abstract-provider";
import { IUniLikeSwapRouter__factory, MintableToken__factory } from "../../typechain";
import hre from "hardhat";
import { ethers } from "hardhat";
import { config } from "../../utils/config";

const ETH_NETWORK_NAME = "ethGoerli";
const POLYGON_NETWORK_NAME = "polygonMumbai";

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
// Deploy btc/eth,  usdc/btc, and usdc/eth pairs
async function deployBtcEth() {
  let [signer] = await ethers.getSigners();

  // mint some usdc to add to pairs
  const usdc = MintableToken__factory.connect(config.l2USDC, signer);
  await usdc.mint(signer.address, 200e6);

  let tokenFactory = await ethers.getContractFactory("MintableToken", signer);
  const btc = await tokenFactory.deploy("Mintable BTC", "BTC", 18, ethers.utils.parseUnits(String(10_000), 18));
  await btc.deployed();
  console.log("BTC ", btc.address);

  const weth = await tokenFactory.deploy("Mintable WETH", "WETH", 18, ethers.utils.parseUnits(String(10_000), 18));
  await weth.deployed();
  console.log("WETH: ", weth.address);

  // We would use btc.address and weth.address but there's bug with getting contract addresses on mumbai via ethers
  // right now
  // This solves the bug in Mumbai network where the contract address is not the real one
  // https://github.com/nomiclabs/hardhat/issues/2162
  let txHash = btc.deployTransaction.hash;
  console.log(`Tx hash: ${txHash}\nWaiting for transaction to be mined...`);
  let txReceipt = await ethers.provider.waitForTransaction(txHash);
  const btcAddr = txReceipt.contractAddress;
  console.log("Real btc address:", btcAddr);

  txHash = weth.deployTransaction.hash;
  console.log(`Tx hash: ${txHash}\nWaiting for transaction to be mined...`);
  txReceipt = await ethers.provider.waitForTransaction(txHash);
  const ethAddr = txReceipt.contractAddress;
  console.log("Real weth address: ", ethAddr);

  // Deploy btc/eth,  usdc/btc, and usdc/eth pairs
  const router = IUniLikeSwapRouter__factory.connect("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", signer);

  // Max approvals
  let tx: TransactionResponse = await btc
    .attach(btcAddr)
    .connect(signer)
    .approve(router.address, ethers.BigNumber.from(2).pow(256).sub(1));
  await tx.wait();
  tx = await weth.attach(ethAddr).connect(signer).approve(router.address, ethers.BigNumber.from(2).pow(256).sub(1));
  await tx.wait();
  tx = await usdc.connect(signer).approve(router.address, ethers.BigNumber.from(2).pow(256).sub(1));
  await tx.wait();

  console.log("approvals done");

  // Add liquidity
  const oneHunderedWeth = ethers.utils.parseUnits(String(100), 18);
  const oneHunderedUsdc = 100e6;
  const deadline = Math.floor(Date.now() / 1000) + 24 * 60 * 60; // unix timestamp in seconds plus 24 hours
  tx = await router.addLiquidity(btcAddr, ethAddr, oneHunderedWeth, oneHunderedWeth, 0, 0, signer.address, deadline, {
    gasLimit: 10e6,
  });
  await tx.wait();

  tx = await router.addLiquidity(
    config.l2USDC,
    btcAddr,
    oneHunderedUsdc,
    oneHunderedWeth,
    0,
    0,
    signer.address,
    deadline,
    { gasLimit: 10e6 },
  );
  await tx.wait();

  tx = await router.addLiquidity(
    config.l2USDC,
    ethAddr,
    oneHunderedUsdc,
    oneHunderedWeth,
    0,
    0,
    signer.address,
    deadline,
    { gasLimit: 10e6 },
  );
  await tx.wait();
  console.log("Liquidity added");
}

deployBtcEth()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
