import { ERC20__factory, IUniswapV2Router02__factory, MockERC20__factory } from "../../typechain";
import hre from "hardhat";
import { ethers } from "hardhat";

import { resolve, join } from "path";
import { readJSON } from "fs-extra";

const ETH_NETWORK_NAME = process.env.ETH_NETWORK || "";
const POLYGON_NETWORK_NAME = process.env.POLYGON_NETWORK || "";

async function useMainnetPrices() {
  const rootDir = resolve(__dirname, "../..");
  const configPath = join(rootDir, "script/config.json");
  const config = await readJSON(configPath);
  console.log({ config });

  hre.changeNetwork(POLYGON_NETWORK_NAME);
  let [signer] = await ethers.getSigners();
  const router = IUniswapV2Router02__factory.connect("0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", signer);
  const btcUsdPool = ERC20__factory.connect("0x48a8E74730Fc1b00fE8a6F4Ef5FA489685c3F7a2", signer);
  const ethUsdPool = ERC20__factory.connect("0xdF95317B41082eb8AFC1CE10eDfE9081CeD39caD", signer);
  const usdc = MockERC20__factory.connect(config.testnet.l2.usdc, signer);
  const btc = MockERC20__factory.connect(config.testnet.l2.wbtc, signer);
  const eth = MockERC20__factory.connect(config.testnet.l2.weth, signer);

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
      [usdc.address, token.address],
      await signer.getAddress(),
      Math.floor(Date.now() / 1000) + 24 * 60 * 60, // unix timestamp in seconds plus 24 hours
    );
    await swap.wait();
  }

  // get quote
  const quotePrice = await router.getAmountsOut(oneToken, [btc.address, usdc.address]);
  console.log(
    "btc quote-price: ",
    quotePrice.map(num => num.toString()),
  );
  const quotePriceEth = await router.getAmountsOut(oneToken, [eth.address, usdc.address]);
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
