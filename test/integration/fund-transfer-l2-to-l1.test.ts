import chai from "chai";
import hre from "hardhat";
import usdcABI from "../assets/usdc-abi.json";

import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { config } from "../../scripts/utils/config";
import { ContractTransaction } from "ethers";
import { deployAll } from "../../scripts/helpers/deploy-all";
import utils from "../utils";
import { address } from "../../scripts/utils/types";

const ETH_NETWORK_NAME = "eth-goerli";
const POLYGON_NETWORK_NAME = "polygon-mumbai";

chai.use(solidity);
const { expect } = chai;

/**
  1) send money to L2 vault
  2) sendTVL (L1)
  3) Receive message (receiveTVL) and send tokens and metadata (L2)
  4) Receive message by posting VAA in bridgeEscrowL1.l1clearfund() after money has arrviced
    - check tvl afterwards
 */
it("Eth-Matic Fund Transfer Integration Test L2 -> L1", async () => {
  let [governance, defender] = await ethers.getSigners();
  const allContracts = await deployAll(
    governance.address,
    governance.address,
    ETH_NETWORK_NAME,
    POLYGON_NETWORK_NAME,
    config,
  );

  const { l1Vault, l2Vault } = allContracts.vaults;
  const { l1WormholeRouter, l2WormholeRouter } = allContracts.wormholeRouters;

  const initialL2TVL = ethers.utils.parseUnits("0.001", 6);

  hre.changeNetwork(POLYGON_NETWORK_NAME);
  [governance, defender] = await ethers.getSigners();
  const polygonUSDC = new ethers.Contract(config.l2USDC, usdcABI, governance);
  console.log("Transfer USDC to L2 vault.");
  let tx: ContractTransaction = await polygonUSDC.transfer(l2Vault.address, initialL2TVL);
  await tx.wait();

  // Send TVL
  hre.changeNetwork(ETH_NETWORK_NAME);
  console.log("\n\nsending TVL");
  tx = await l1Vault.sendTVL();
  await tx.wait();

  // Receive message (receiveTVL) and send tokens with a wormhole message containing the amount sent
  let l1Sequence = 0;
  const tvlVAA = await utils.getVAA(l1WormholeRouter.address, String(l1Sequence), 2);
  l1Sequence += 1;

  hre.changeNetwork(POLYGON_NETWORK_NAME);
  console.log("\n\nreceiving TVL on L2");
  [, defender] = await ethers.getSigners();
  tx = await l2WormholeRouter.connect(defender).receiveTVL(tvlVAA, { gasLimit: 10_000_000 });
  await tx.wait();
  console.log("TVL received. Sending tokens to L1");

  // Get burn proof
  const messageProof = await utils.waitForL2MessageProof(
    "https://apis.matic.network/api/v1/mumbai",
    tx.hash,
    "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", // ERC20 transfer event sig.
  );

  // Get VAA
  const transferVAA = await utils.getVAA(l2WormholeRouter.address, String(0), 5);

  // Post burn proof and VAA to clear funds
  const bridgeEscrowAddr: address = await l2Vault.bridgeEscrow();
  console.log("BridgeEscrow Address: ", bridgeEscrowAddr);

  // clear funds on L1
  hre.changeNetwork(ETH_NETWORK_NAME);
  [, defender] = await ethers.getSigners();

  console.log("Clearing funds from bridgeEscrow");
  tx = await l1WormholeRouter.connect(defender).receiveFunds(transferVAA, ethers.utils.arrayify(messageProof));
  await tx.wait();

  expect(await l1Vault.vaultTVL()).to.eq(initialL2TVL.mul(90).div(100));
});
