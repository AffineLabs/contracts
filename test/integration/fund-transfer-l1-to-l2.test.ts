import chai from "chai";
import hre from "hardhat";
import usdcABI from "../assets/usdc-abi.json";

import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { config } from "scripts/utils/config";
import { ContractTransaction } from "ethers";
import { getTxExplorerLink } from "scripts/utils/bc-explorer-links";
import { AllContracts, deployAll } from "scripts/helpers/deploy-all";
import utils from "../utils";

const ETH_NETWORK_NAME = "ethGoerli";
const POLYGON_NETWORK_NAME = "polygonMumbai";

chai.use(solidity);
const { expect } = chai;

/**
  1) send money to L1 vault
  2) sendTVL (L1)
  3) Receive message (receiveTVL) and send a message to L1 with amount request (L2)
  4) Receive message by posting VAA with vaultL1.receiveMessage (L1)
    - bridge tokens and send metadata in message to L2
  5) Receive message by posting VAA in stagingL2.l2clearfund() after bridging transaction has completed (L2)
    - check tvl afterwards
 */

it("Eth-Matic Fund Transfer Integration Test L1 -> L2", async () => {
  let [governance] = await ethers.getSigners();
  const allContracts: AllContracts = await deployAll(
    governance.address,
    governance.address,
    ETH_NETWORK_NAME,
    POLYGON_NETWORK_NAME,
    config,
  );

  const { l1Vault, l2Vault } = allContracts.vaults;

  const initialL1TVL = ethers.utils.parseUnits("0.001", 6);

  hre.changeNetwork(ETH_NETWORK_NAME);
  [governance] = await ethers.getSigners();

  // Transfer some USDC from owner to L1 vault.
  const ethUSDC = new ethers.Contract(config.l1USDC, usdcABI, governance);
  let tx: ContractTransaction = await ethUSDC.transfer(l1Vault.address, initialL1TVL);
  await tx.wait();
  expect(await ethUSDC.balanceOf(l1Vault.address)).to.eq(initialL1TVL);

  const currentL1TVL = await l1Vault.vaultTVL();
  expect(currentL1TVL).to.eq(initialL1TVL);

  // Send TVL
  console.log("\n\nsending TVL");
  tx = await l1Vault.sendTVL();
  await tx.wait();

  // Receive message (receiveTVL) and send a message to L1 with amount request (L2)
  // sequence is the number of transactions we've sent to wormhole from a given address
  let l1Sequence = 0;
  const tvlVAA = await utils.getVAA(l1Vault.address, String(l1Sequence), 2);
  l1Sequence += 1;

  hre.changeNetwork(POLYGON_NETWORK_NAME);
  console.log("\n\nreceiving TVL on L2");
  [governance] = await ethers.getSigners();
  tx = await l2Vault.connect(governance).receiveTVL(tvlVAA);
  await tx.wait();
  console.log("TVL received");

  // L2 just sent an amount request to L1, receive this message here
  let l2Sequence = 0;
  const requestVAA = await utils.getVAA(l2Vault.address, String(l2Sequence), 5);
  l2Sequence += 1;

  hre.changeNetwork(ETH_NETWORK_NAME);
  [governance] = await ethers.getSigners();
  tx = await l1Vault.connect(governance).receiveMessage(requestVAA, { gasLimit: 10_000_000 });
  await tx.wait();
  console.log("Received request from L2 on L1. Transfer from L1 to L2 initiated.");

  // L1 just sent money along with a message to L2
  // Wait for money to hit staging, then use message to clear funds from staging to l2 vault
  // Get instance of staging contract
  hre.changeNetwork(POLYGON_NETWORK_NAME);
  [governance] = await ethers.getSigners();
  const l2Staging = (await ethers.getContractFactory("Staging", governance)).attach(await l2Vault.staging());
  console.log("L2 staging address: ", l2Staging.address);

  await utils.waitForNonZeroAddressTokenBalance(
    config.l2USDC,
    usdcABI,
    "L2 Staging",
    l2Staging.address,
    ethers.provider,
  );
  console.log("\n\nStaging contract has received funds. Getting transfer VAA from L1 Vault");

  const transferVAA = await utils.getVAA(l1Vault.address, String(l1Sequence), 2);
  l1Sequence += 1;

  console.log("Clearing funds from staging");
  tx = await l2Staging.connect(governance).l2ClearFund(transferVAA);
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(POLYGON_NETWORK_NAME, tx)}`);

  expect(await l2Vault.vaultTVL()).to.eq(initialL1TVL.div(10));
});
