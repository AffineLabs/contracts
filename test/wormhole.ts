import chai from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { config } from "../utils/config";
import { Contract, ContractTransaction } from "ethers";
import { getSignedVAA, getEmitterAddressEth } from "@certusone/wormhole-sdk";
import { NodeHttpTransport } from "@improbable-eng/grpc-web-node-http-transport";

import scriptUtils from "../scripts/utils";
import usdcABI from "./assets/usdc-abi.json";

const ETH_NETWORK_NAME = "ethGoerli";
const POLYGON_NETOWRK_NAME = "polygonMumbai";

chai.use(solidity);
const { expect } = chai;

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

it("Can send and receive TVL info", async () => {
  const registry = await scriptUtils.deployContractRegistry(ETH_NETWORK_NAME, POLYGON_NETOWRK_NAME);
  let [governance, defender] = await ethers.getSigners();

  // deploy vault
  const { L1VaultContract: l1Vault, L2VaultContract: l2Vault } = await scriptUtils.deployVaults(
    ETH_NETWORK_NAME,
    config.l1USDC,
    POLYGON_NETOWRK_NAME,
    config.l2USDC,
    governance.address,
    registry,
    config.l1worm,
    config.l2worm,
  );

  //////////////////// ETH transactions - need to call getSigners after every network change
  // signers have provider attached to them
  hre.changeNetwork(ETH_NETWORK_NAME);
  [governance, defender] = await ethers.getSigners();

  const initialL1TVL = ethers.utils.parseUnits("0.001", 6);
  const ethUSDCContract: Contract = new ethers.Contract(config.l1USDC, usdcABI, governance);
  let tx: ContractTransaction = await ethUSDCContract.transfer(l1Vault.address, initialL1TVL);
  await tx.wait();
  // Send TVL
  console.log("tvl of L1 vault: ", (await l1Vault.vaultTVL()).toString());
  const sendTx: ContractTransaction = await l1Vault.connect(defender).sendTVL();
  console.log("Sending msg to wormhole");
  await sendTx.wait();

  //////////////////// POLYGON transactions
  hre.changeNetwork(POLYGON_NETOWRK_NAME);
  [governance, defender] = await ethers.getSigners();

  // Receive TVL
  let result;
  let attempts = 0;
  const maxAttempts = 60;
  while (!result) {
    console.log("waiting for VAA");
    attempts += 1;
    await sleep(5000);
    // get signed vaa

    try {
      result = await getSignedVAA(
        "https://wormhole-v2-testnet-api.certus.one",
        2,
        getEmitterAddressEth(l1Vault.address),
        "0",
        { transport: NodeHttpTransport() },
      );
    } catch (e) {
      if (attempts > maxAttempts) throw e;
    }
  }

  // send vaa to receiver contract on polygon
  const vaaTx = await l2Vault.connect(defender).receiveTVL(result.vaaBytes);
  await vaaTx.wait();

  const receivedTVL = await l2Vault.L1TotalLockedValue();
  console.log("received tvl: ", receivedTVL.toString());
  // assert that tvl number is correct
  expect(receivedTVL).to.equal(initialL1TVL);
});
