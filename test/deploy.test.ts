import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";

import { mainnetConfig } from "../scripts/utils/config";
import { deployAll } from "../scripts/helpers/deploy-all";

chai.use(solidity);
const { expect } = chai;

describe("Deploy All", async () => {
  it("Can deploy all contracts", async () => {
    const config = mainnetConfig;

    const allContracts = await deployAll(
      config.l1.governance,
      config.l2.governance,
      process.env.ETH_NETWORK || "eth-goerli-fork",
      process.env.POLYGON_NETWORK || "polygon-mumbai-fork",
      config,
    );
    const {
      vaults: { l1Vault, l2Vault, emergencyWithdrawalQueue, l1BridgeEscrow, l2BridgeEscrow },
      forwarder,
      wormholeRouters,
      basket,
    } = allContracts;

    // Tokens are set correctly
    expect(await l2Vault.asset()).to.equal(config.l2.usdc);
    expect(await l1Vault.asset()).to.equal(config.l1.usdc);

    const forwarderAddr = await l2Vault.trustedForwarder();
    expect(forwarderAddr).to.be.properAddress;
    expect(forwarderAddr).to.not.equal(ethers.constants.AddressZero);
    expect(forwarderAddr).to.equal(forwarder.address);

    // Check that bridgeEscrow addresses are the same + are both initialized correctly
    expect(l1BridgeEscrow.address).to.equal(l2BridgeEscrow.address);
    expect(await l1BridgeEscrow.token()).to.equal(await l1Vault.asset());
    expect(await l1BridgeEscrow.wormholeRouter()).to.equal(await l1Vault.wormholeRouter());
    expect(await l2BridgeEscrow.token()).to.equal(await l2Vault.asset());
    expect(await l2BridgeEscrow.wormholeRouter()).to.equal(await l2Vault.wormholeRouter());

    // Check emergency withdrawal queue deployment
    expect(await l2Vault.emergencyWithdrawalQueue()).to.equal(emergencyWithdrawalQueue.address);
    expect(await emergencyWithdrawalQueue.vault()).to.equal(l2Vault.address);

    expect(await wormholeRouters.l1WormholeRouter.wormhole()).to.equal(config.l1.wormhole);
    expect(await wormholeRouters.l2WormholeRouter.wormhole()).to.equal(config.l2.wormhole);

    // Check wormhole routers
    expect(await wormholeRouters.l1WormholeRouter.wormhole()).to.equal(config.l1.wormhole);
    expect(await wormholeRouters.l2WormholeRouter.wormhole()).to.equal(config.l2.wormhole);

    expect(await l1Vault.wormholeRouter()).to.equal(wormholeRouters.l1WormholeRouter.address);
    expect(await l2Vault.wormholeRouter()).to.equal(wormholeRouters.l2WormholeRouter.address);

    expect(await l1Vault.wormholeRouter()).to.equal(wormholeRouters.l1WormholeRouter.address);
    expect(await l2Vault.wormholeRouter()).to.equal(wormholeRouters.l2WormholeRouter.address);

    expect(await wormholeRouters.l1WormholeRouter.otherLayerRouter()).to.equal(
      wormholeRouters.l2WormholeRouter.address,
    );
    expect(await wormholeRouters.l2WormholeRouter.otherLayerRouter()).to.equal(
      wormholeRouters.l1WormholeRouter.address,
    );

    expect(await basket.asset()).to.equal(config.l2.usdc);
    expect(await basket.btc()).to.equal(config.l2.wbtc);
    expect(await basket.weth()).to.equal(config.l2.weth);
  });
});
