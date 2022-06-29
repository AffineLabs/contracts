import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";

import { deployVaults } from "../scripts/helpers/deploy-vaults";
import { deployWormholeRouters } from "../scripts/helpers/deploy-wormhole-router";
import { config } from "../scripts/utils/config";
import { deployBasket } from "../scripts/helpers/deploy-btc-eth";

chai.use(solidity);
const { expect } = chai;

it("Deploy Vaults", async () => {
  const wormholeRouters = await deployWormholeRouters(
    process.env.ETH_NETWORK || "eth-goerli-fork",
    process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
  );
  const { l1Vault, l2Vault } = await deployVaults(
    config.l1Governance,
    config.l2Governance,
    process.env.ETH_NETWORK || "eth-goerli-fork",
    process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    config,
    wormholeRouters,
  );

  // If tokens are set correctly, most likely everything else is.
  expect(await l2Vault.asset()).to.equal(config.l2USDC);
  expect(await l1Vault.asset()).to.equal(config.l1USDC);

  const forwarder = await l2Vault.trustedForwarder();
  expect(forwarder).to.be.properAddress;
  expect(forwarder).to.not.equal(ethers.constants.AddressZero);
  expect(forwarder).to.equal(config.forwarder);

  // Check that bridgeEscrow addresses are the same
  const l1BridgeEscrow = await l1Vault.bridgeEscrow();
  expect(l1BridgeEscrow).to.be.properAddress;
  expect(l1BridgeEscrow).to.equal(await l2Vault.bridgeEscrow());

  // Check wormhole routers
  expect(await l1Vault.wormholeRouter()).to.equal(wormholeRouters.l1WormholeRouter.address);
  expect(await l2Vault.wormholeRouter()).to.equal(wormholeRouters.l2WormholeRouter.address);

  expect(await wormholeRouters.l1WormholeRouter.wormhole()).to.equal(config.l1worm);
  expect(await wormholeRouters.l2WormholeRouter.wormhole()).to.equal(config.l2worm);

  expect(await wormholeRouters.l1WormholeRouter.l2WormholeRouterAddress()).to.equal(wormholeRouters.l2WormholeRouter.address);
  expect(await wormholeRouters.l2WormholeRouter.l1WormholeRouterAddress()).to.equal(wormholeRouters.l1WormholeRouter.address);
});

// TODO: check that we can upgrade proxies successfully

it("Deploy TwoAssetBasket", async () => {
  const basket = await deployBasket(config);
  expect(await basket.asset()).to.equal(config.l2USDC);
  expect(await basket.token1()).to.equal(config.wbtc);
  expect(await basket.token2()).to.equal(config.weth);
});
