import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";

import { deployVaults } from "../scripts/helpers/deploy-vaults";
import { deployWormholeRouters } from "../scripts/helpers/deploy-wormhole-router";
import { config } from "../scripts/utils/config";

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
  expect(await l2Vault.token()).to.equal(config.l2USDC);
  expect(await l1Vault.token()).to.equal(config.l1USDC);

  const forwarder = await l2Vault.trustedForwarder();
  expect(forwarder).to.be.properAddress;
  expect(forwarder).to.not.equal(ethers.constants.AddressZero);
  expect(forwarder).to.equal(config.forwarder);

  // Check that bridgeEscrow addresses are the same
  const l1BridgeEscrow = await l1Vault.bridgeEscrow();
  expect(l1BridgeEscrow).to.be.properAddress;
  expect(l1BridgeEscrow).to.equal(await l2Vault.bridgeEscrow());
});

// TODO: check that we can upgrade proxies successfully
