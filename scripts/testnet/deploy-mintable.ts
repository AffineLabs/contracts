import { ERC20__factory, IUniLikeSwapRouter__factory, MintableToken__factory, Router__factory } from "../../typechain";
import hre from "hardhat";
import { ethers } from "hardhat";
import { config } from "../utils/config";
import { getContractAddress } from "../utils/export";

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

const MAX_UINT_256 = ethers.BigNumber.from(2).pow(256).sub(1);

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
  const btcPrice = 19.5e3;
  const ethPrice = 1080;
  const amountUSDC = ethers.BigNumber.from(100e6);
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  let [signer] = await ethers.getSigners();
  const { wbtc: btcAddr, weth: ethAddr } = config;

  const router = IUniLikeSwapRouter__factory.connect("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", signer);
  const usdc = MintableToken__factory.connect(config.l2USDC, signer);
  const btc = MintableToken__factory.connect(btcAddr, signer);
  const eth = MintableToken__factory.connect(ethAddr, signer);

  const oneToken = ethers.BigNumber.from(10).pow(18);
  const oneHunderedMUsdc = amountUSDC.mul(1e6);
  const oneHunderedMBtc = amountUSDC.div(btcPrice).mul(oneToken);
  const oneHundredMEth = amountUSDC.div(ethPrice).mul(oneToken);

  // Mint some tokens
  let tx = await usdc.mint(signer.address, oneHunderedMUsdc.mul(2));
  await tx.wait();
  tx = await btc.mint(signer.address, oneHunderedMBtc);
  await tx.wait();
  tx = await eth.mint(signer.address, oneHundredMEth);
  await tx.wait();

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
  );
  await tx.wait();
  console.log("Liquidity added");
}

async function removeLiquidity() {
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  let [signer] = await ethers.getSigners();
  const router = IUniLikeSwapRouter__factory.connect("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", signer);

  // TODO: get pair addresses via uniswap sdk. Hardcoding for now
  const btcUsdPool = ERC20__factory.connect("0x48a8E74730Fc1b00fE8a6F4Ef5FA489685c3F7a2", signer);
  const ethUsdPool = ERC20__factory.connect("0xdF95317B41082eb8AFC1CE10eDfE9081CeD39caD", signer);

  const approveBtc = await btcUsdPool.approve(router.address, MAX_UINT_256);
  await approveBtc.wait();

  const approveWeth = await ethUsdPool.approve(router.address, MAX_UINT_256);
  await approveWeth.wait();
  console.log("approvals done", approveWeth.hash);

  console.log("removing BTC liquidity");
  const removeBtcTx = await router.removeLiquidity(
    config.wbtc,
    config.l2USDC,
    await btcUsdPool.balanceOf(await signer.getAddress()),
    0,
    0,
    await signer.getAddress(),
    Math.floor(Date.now() / 1000) + 24 * 60 * 60, // unix timestamp in seconds plus 24 hours
  );
  await removeBtcTx.wait();

  console.log("removing ETH liquidity");

  const removeEthTx = await router.removeLiquidity(
    config.weth,
    config.l2USDC,
    await ethUsdPool.balanceOf(await signer.getAddress()),
    0,
    0,
    await signer.getAddress(),
    Math.floor(Date.now() / 1000) + 24 * 60 * 60, // unix timestamp in seconds plus 24 hours
  );
  await removeEthTx.wait();
}

async function useMainnetPrices() {
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  let [signer] = await ethers.getSigners();
  const router = IUniLikeSwapRouter__factory.connect("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", signer);
  const btcUsdPool = ERC20__factory.connect("0x48a8E74730Fc1b00fE8a6F4Ef5FA489685c3F7a2", signer);
  const ethUsdPool = ERC20__factory.connect("0xdF95317B41082eb8AFC1CE10eDfE9081CeD39caD", signer);
  const usdc = MintableToken__factory.connect(config.l2USDC, signer);
  const btc = MintableToken__factory.connect(config.wbtc, signer);
  const eth = MintableToken__factory.connect(config.weth, signer);

  const tokenToPrice = { btc: 22_912, eth: 1_614 };
  const tokenToPool = { btc: btcUsdPool, eth: ethUsdPool };
  const tokenToContract = { btc, eth };

  const tokens: ["btc", "eth"] = ["btc", "eth"];
  const oneToken = ethers.BigNumber.from(10).pow(18);
  for (const name of tokens) {
    const token = tokenToContract[name];
    const pool = tokenToPool[name];
    const price = tokenToPrice[name];
    const tokenBal = await token.balanceOf(pool.address);

    const tokenDollars = await tokenBal.div(oneToken).mul(price);
    const usdcDollars = (await usdc.balanceOf(pool.address)).div(1e6);

    if (usdcDollars.gt(tokenDollars)) {
      console.log("minting btc or eth");
      const numTokenNeeded = usdcDollars.sub(tokenDollars).div(price).mul(oneToken);
      const tx = await token.mint(pool.address, numTokenNeeded);
      console.log("tx: ", tx);
      await tx.wait();
    }

    if (tokenDollars.gt(usdcDollars)) {
      console.log("minting usdc");
      const numUsdcNeeded = tokenDollars.sub(usdcDollars).mul(1e6);
      const tx = await usdc.mint(pool.address, numUsdcNeeded);
      await tx.wait();
    }

    // We do this swap to update the pool reserves to account for the transferred tokens
    // The next swap after this one will happen at the prices given above
    const swap = await router.swapExactTokensForTokens(
      1e6,
      0,
      [config.l2USDC, token.address],
      await signer.getAddress(),
      Math.floor(Date.now() / 1000) + 24 * 60 * 60, // unix timestamp in seconds plus 24 hours
    );
    await swap.wait();
  }

  // get quote
  const quotePrice = await router.getAmountsOut(oneToken, [config.wbtc, config.l2USDC]);
  console.log(
    "btc quote-price: ",
    quotePrice.map(num => num.toString()),
  );
  const quotePriceEth = await router.getAmountsOut(oneToken, [config.weth, config.l2USDC]);
  console.log(
    "eth quote-price: ",
    quotePriceEth.map(num => num.toString()),
  );
}

useMainnetPrices()
  .then(() => {
    process.exit(0);
  })
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
