import { ethers, upgrades, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";

import { deployVaults } from "../scripts/helpers/deploy-vaults";
import { deployWormholeRouters } from "../scripts/helpers/deploy-wormhole-router";
import { testConfig } from "../scripts/utils/config";
import { deployBasket } from "../scripts/helpers/deploy-btc-eth";
import { deployForwarder } from "scripts/fixtures/deploy-forwarder";

chai.use(solidity);
const { expect } = chai;

describe("Deploy AlpSave", async () => {
  it("Deploy Vaults", async () => {
    const config = testConfig;
    const forwarder = await deployForwarder(process.env.POLYGON_NETWORK || "polygon-mumbai-fork");
    const wormholeRouters = await deployWormholeRouters(
      process.env.ETH_NETWORK || "eth-goerli-fork",
      process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    );
    const { l1Vault, l2Vault, emergencyWithdrawalQueue } = await deployVaults(
      testConfig.l1.governance,
      testConfig.l2.governance,
      process.env.ETH_NETWORK || "eth-goerli-fork",
      process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
      config,
      wormholeRouters,
      forwarder,
    );

    // If tokens are set correctly, most likely everything else is.
    expect(await l2Vault.asset()).to.equal(testConfig.l2.usdc);
    expect(await l1Vault.asset()).to.equal(testConfig.l1.usdc);

    const forwarderAddr = await l2Vault.trustedForwarder();
    expect(forwarderAddr).to.be.properAddress;
    expect(forwarderAddr).to.not.equal(ethers.constants.AddressZero);
    expect(forwarder).to.equal(forwarder.address);

    // Check that bridgeEscrow addresses are the same
    const l1BridgeEscrow = await l1Vault.bridgeEscrow();
    expect(l1BridgeEscrow).to.be.properAddress;
    expect(l1BridgeEscrow).to.equal(await l2Vault.bridgeEscrow());

    // Check wormhole routers
    expect(await l1Vault.wormholeRouter()).to.equal(wormholeRouters.l1WormholeRouter.address);
    expect(await l2Vault.wormholeRouter()).to.equal(wormholeRouters.l2WormholeRouter.address);

    // Check emergency withdrawal queue deployment
    expect(await l2Vault.emergencyWithdrawalQueue()).to.equal(emergencyWithdrawalQueue.address);
    expect(await emergencyWithdrawalQueue.vault()).to.equal(l2Vault.address);

    expect(await wormholeRouters.l1WormholeRouter.wormhole()).to.equal(config.l1.wormhole);
    expect(await wormholeRouters.l2WormholeRouter.wormhole()).to.equal(config.l2.wormhole);

    expect(await wormholeRouters.l1WormholeRouter.otherLayerRouter()).to.equal(
      wormholeRouters.l2WormholeRouter.address,
    );
    expect(await wormholeRouters.l2WormholeRouter.otherLayerRouter()).to.equal(
      wormholeRouters.l1WormholeRouter.address,
    );
  });
});

describe("Deploy AlpLarge", async () => {
  it("Deploy TwoAssetBasket", async () => {
    const forwarder = await deployForwarder(process.env.POLYGON_NETWORK || "polygon-mumbai-fork");
    const basket = await deployBasket(testConfig, forwarder);
    expect(await basket.asset()).to.equal(testConfig.l2.usdc);
    expect(await basket.btc()).to.equal(testConfig.l2.wbtc);
    expect(await basket.weth()).to.equal(testConfig.l2.weth);
  });
});
