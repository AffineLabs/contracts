import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";

import { deployVaults } from "../scripts/utils/deploy-vaults";
import { config } from "../utils/config";

chai.use(solidity);
const { expect } = chai;

const ETH_NETWORK_NAME = "eth-goerli";
const POLYGON_NETWORK_NAME = "polygon-mumbai";

it("Deploy Vaults", async () => {
  const { l1Vault, l2Vault, relayer } = await deployVaults(
    config.l1Governance,
    config.l2Governance,
    ETH_NETWORK_NAME,
    POLYGON_NETWORK_NAME,
    config,
  );

  // If tokens are set correctly, most likely everything else is.
  expect(await l2Vault.token()).to.equal(config.l2USDC);
  expect(await l1Vault.token()).to.equal(config.l1USDC);

  const actualRelayer = await l2Vault.relayer();
  expect(actualRelayer).to.be.properAddress;
  expect(actualRelayer).to.not.equal(ethers.constants.AddressZero);
  expect(actualRelayer).to.equal(relayer.address);

  // Check that staging addresses are the same
});

// TODO: check that we can upgrade proxies successfully
