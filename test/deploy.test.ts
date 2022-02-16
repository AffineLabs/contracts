import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";

import { deployVaults } from "../scripts/utils/deploy-vaults";
import { config } from "../utils/config";

chai.use(solidity);
const { expect } = chai;

const ETH_NETWORK_NAME = "ethGoerli";
const POLYGON_NETWORK_NAME = "polygonMumbai";

it("Deploy Vaults", async () => {
  let [governance] = await ethers.getSigners();
  const { l1Vault, l2Vault } = await deployVaults(governance.address, governance.address, ETH_NETWORK_NAME, POLYGON_NETWORK_NAME, config);

  // If tokens are set correctly, most likely everything else is. TODO: add a couple more asserts
  expect(await l2Vault.token()).to.equal(config.l2USDC);
  expect(await l1Vault.token()).to.equal(config.l1USDC);
});

// TODO: check that we can upgrade proxies successfully
