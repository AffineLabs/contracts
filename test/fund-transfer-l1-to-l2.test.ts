import chai from "chai";
import hre from "hardhat";
import usdcABI from "./assets/usdc-abi.json";

import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { config } from "../utils/config";
import { Contract, ContractTransaction } from "ethers";
import { getTxExplorerLink } from "../utils/bc-explorer-links";
import { AllContracts, deployAll } from "../scripts/utils/deploy-all";
import { waitForL2MessageProof, waitForNonZeroAddressTokenBalance } from "./utils/wait-utils";

const ETH_NETWORK_NAME = "ethGoerli";
const POLYGON_NETOWRK_NAME = "polygonMumbai";

chai.use(solidity);
const { expect } = chai;

it("Eth-Matic Fund Transfer Integration Test L1 -> L2", async () => {
  let l1Vault: Contract;
  let l2Vault: Contract;
  let l2Staging: Contract;
  let l1FxTunnel: Contract;

  let [governance, defender] = await ethers.getSigners();
  const allContracts: AllContracts = await deployAll(
    governance.address,
    defender.address,
    ETH_NETWORK_NAME,
    POLYGON_NETOWRK_NAME,
    config.checkpointManager,
    config.l1ChainManager,
    config.l1USDC,
    config.l1FxTunnel,
    config.l2USDC,
    config.l2ERC20Predicate,
    config.l2FxTunnel,
    config.create2Deployer,
  );

  l1Vault = allContracts.vaultContracts.L1VaultContract;
  l2Vault = allContracts.vaultContracts.L2VaultContract;
  l2Staging = allContracts.stagingContract.L2StagingContract;
  l1FxTunnel = allContracts.fxTunnelContracts.L1FxTunnel;

  const initialL1TVL = ethers.utils.parseUnits("0.001", 6);

  hre.changeNetwork(ETH_NETWORK_NAME);
  [governance, defender] = await ethers.getSigners();
  // Transfer some USDC from owner to L1 vault.
  const ethUSDCContract: Contract = new ethers.Contract(config.l1USDC, usdcABI, governance);
  let tx: ContractTransaction = await ethUSDCContract.transfer(l1Vault.address, initialL1TVL);
  await tx.wait();
  expect(await ethUSDCContract.balanceOf(l1Vault.address)).to.eq(initialL1TVL);

  // Get L1 TVL from L1 Vault.
  const currentL1TVL = await l1Vault.vaultTVL();
  expect(currentL1TVL).to.eq(initialL1TVL);

  hre.changeNetwork(POLYGON_NETOWRK_NAME);
  [governance, defender] = await ethers.getSigners();
  console.log("Setting L1 TVL in L2 Vault.");
  tx = await l2Vault.connect(defender).setL1TVL(currentL1TVL);
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(POLYGON_NETOWRK_NAME, tx)}`);

  console.log("Trigger of rebalance in L2 Vault.");
  tx = await l2Vault.connect(defender).L1L2Rebalance();
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(POLYGON_NETOWRK_NAME, tx)}`);

  const fxChildTxHash = tx.hash;
  const messageProof = await waitForL2MessageProof(
    "https://apis.matic.network/api/v1/mumbai",
    fxChildTxHash,
    "0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036", // Send MSG event sig
  );

  hre.changeNetwork(ETH_NETWORK_NAME);
  [governance, defender] = await ethers.getSigners();
  console.log("Record debt amount in L1 Vault by presending L2 Vault message proof.");
  tx = await l1FxTunnel.connect(defender).receiveMessage(ethers.utils.arrayify(messageProof));
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(ETH_NETWORK_NAME, tx)}`);

  console.log("L1 debt to L2", (await l1Vault.debtToL2()).toString());
  expect(await l1Vault.debtToL2()).to.eq(initialL1TVL.div(10));

  console.log("Initiate transfer of L1 debt to L2.");
  tx = await l1Vault.connect(defender).l2Rebalance();
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(ETH_NETWORK_NAME, tx)}`);

  expect(await l1Vault.vaultTVL()).to.eq(initialL1TVL.div(10).mul(9));

  await waitForNonZeroAddressTokenBalance(
    POLYGON_NETOWRK_NAME,
    config.l2USDC,
    usdcABI,
    "L2 Staging",
    l2Staging.address,
  );

  hre.changeNetwork(POLYGON_NETOWRK_NAME);
  [governance, defender] = await ethers.getSigners();
  const polygonUSDCContract: Contract = new ethers.Contract(config.l2USDC, usdcABI, governance);
  console.log("L2 Staging contract balance:", (await polygonUSDCContract.balanceOf(l2Staging.address)).toString());

  const l1VaultLastTransferBlockNum = await l1Vault.lastTransferBlockNum();
  const l1VaultLastTransferAmount = await l1Vault.lastTransferAmount();

  console.log(
    `Calling clear fund in L2 staging contract with params: (${l1VaultLastTransferBlockNum}, ${l1VaultLastTransferAmount})`,
  );
  tx = await l2Staging.connect(defender).l2ClearFund(l1VaultLastTransferBlockNum, l1VaultLastTransferAmount);
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(POLYGON_NETOWRK_NAME, tx)}`);

  console.log("L2 Staging contract balance:", (await polygonUSDCContract.balanceOf(l2Staging.address)).toString());
  expect(await l2Vault.vaultTVL()).to.eq(initialL1TVL.div(10));
});
