import { ethers, upgrades, network } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";

import { deployVaults } from "../scripts/helpers/deploy-vaults";
import { deployWormholeRouters } from "../scripts/helpers/deploy-wormhole-router";
import { config } from "../scripts/utils/config";
import { deployBasket } from "../scripts/helpers/deploy-btc-eth";

chai.use(solidity);
const { expect } = chai;

describe("Deploy AlpSave", async () => {
  it("Deploy Vaults", async () => {
    const wormholeRouters = await deployWormholeRouters(
      process.env.ETH_NETWORK || "eth-goerli-fork",
      process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    );
    const { l1Vault, l2Vault, emergencyWithdrawalQueue } = await deployVaults(
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

    // Check emergency withdrawal queue deployment
    expect(await l2Vault.emergencyWithdrawalQueue()).to.equal(emergencyWithdrawalQueue.address);
    expect(await emergencyWithdrawalQueue.vault()).to.equal(l2Vault.address);

    expect(await wormholeRouters.l1WormholeRouter.wormhole()).to.equal(config.l1worm);
    expect(await wormholeRouters.l2WormholeRouter.wormhole()).to.equal(config.l2worm);

    expect(await wormholeRouters.l1WormholeRouter.l2WormholeRouterAddress()).to.equal(
      wormholeRouters.l2WormholeRouter.address,
    );
    expect(await wormholeRouters.l2WormholeRouter.l1WormholeRouterAddress()).to.equal(
      wormholeRouters.l1WormholeRouter.address,
    );
  });

  it("We can upgrade the the L2 Vault", async () => {
    // deploy a new l2vault
    const wormholeRouters = await deployWormholeRouters(
      process.env.ETH_NETWORK || "eth-goerli-fork",
      process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
    );
    const { l2Vault: oldL2Vault } = await deployVaults(
      config.l1Governance,
      config.l2Governance,
      process.env.ETH_NETWORK || "eth-goerli-fork",
      process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
      config,
      wormholeRouters,
    );
    const { l2Vault: newL2Vault } = await deployVaults(
      config.l1Governance,
      config.l2Governance,
      process.env.ETH_NETWORK || "eth-goerli-fork",
      process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
      config,
      wormholeRouters,
    );

    // Both vaults actually have the same implementation address already
    // https://forum.openzeppelin.com/t/truffle-upgrades-upgrading-to-the-same-implementation-address/29882/2
    console.log("old implementation: ", await upgrades.erc1967.getImplementationAddress(oldL2Vault.address));
    const newImplementation = await upgrades.erc1967.getImplementationAddress(newL2Vault.address);
    console.log("new implementation: ", newImplementation);

    // Give timelock addr some eth, no leading zeroes allowed in hex string: https://github.com/NomicFoundation/hardhat/issues/1585
    await network.provider.send("hardhat_setBalance", [
      config.l2Governance,
      ethers.utils.parseEther("10").toHexString(),
    ]);
    // Impersonate timelock address
    // See this issue: https://github.com/NomicFoundation/hardhat/issues/1226#issuecomment-1181706467
    const provider = new ethers.providers.JsonRpcProvider("http://localhost:8546");
    await provider.send("hardhat_impersonateAccount", [config.l2Governance]);
    const account = provider.getSigner(config.l2Governance);

    console.log("impersonation completed");
    // call upgradeTo
    await oldL2Vault.connect(account).upgradeTo(newImplementation);
    expect(await upgrades.erc1967.getImplementationAddress(oldL2Vault.address)).to.equal(newImplementation);
  });
});

describe("Deploy AlpLarge", async () => {
  it("Deploy TwoAssetBasket", async () => {
    const basket = await deployBasket(config);
    expect(await basket.asset()).to.equal(config.l2USDC);
    expect(await basket.token1()).to.equal(config.wbtc);
    expect(await basket.token2()).to.equal(config.weth);
  });
});
