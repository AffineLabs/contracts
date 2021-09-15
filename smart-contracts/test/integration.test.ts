import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import hre from "hardhat";
import { assert } from 'console';
import { Contract, ContractFactory } from 'ethers';
import axios, { AxiosError } from 'axios';

dotenvConfig({ path: resolve(__dirname, "./.env") });

const CHECKPOINT_MANAGER = process.env.CHECKPOINT_MANAGER || "";
const FX_ROOT = process.env.FX_ROOT || "";
const FX_CHILD = process.env.FX_CHILD || "";
const INFURA_API_KEY = process.env.INFURA_API_KEY || "";

assert(CHECKPOINT_MANAGER !== "", "Checkpint Manager address must not be empty. Please set CHECKPOINT_MANAGER in the .env file.");
assert(FX_ROOT !== "", "Fx root address must not be empty. Please set FX_ROOT in the .env file.");
assert(FX_CHILD !== "", "Fx child address must not be empty. Please set FX_CHILD in the .env file.");
assert(INFURA_API_KEY !== "", "Infura API Key must not be empty. Please set INFURA_API_KEY in the .env file.");


chai.use(solidity);
const { expect } = chai;

describe("Eth-Matic Bridge Integration Test", () => {
  let fxStateRootTunnel: Contract;
  let fxStateChildTunnel: Contract;

  // Runs once before running all tests.
  before(async() => {
    hre.changeNetwork('ethGoerli');
    const FxStateRootTunnelFactory: ContractFactory = await ethers.getContractFactory('FxStateRootTunnel');
    fxStateRootTunnel = await FxStateRootTunnelFactory.deploy(CHECKPOINT_MANAGER, FX_ROOT);
    await fxStateRootTunnel.deployed();
    hre.changeNetwork('polygonMumbai');
    const FxStateChildTunnelFactory: ContractFactory = await ethers.getContractFactory('FxStateChildTunnel');
    fxStateChildTunnel = await FxStateChildTunnelFactory.deploy(FX_CHILD);
    await fxStateChildTunnel.deployed();
    hre.changeNetwork('ethGoerli');
    await fxStateRootTunnel.setFxChildTunnel(fxStateChildTunnel.address)
    hre.changeNetwork('polygonMumbai');
    await fxStateChildTunnel.setFxRootTunnel(fxStateRootTunnel.address)
  });

  // Runs before each test.
  beforeEach(async () => {});

  describe("L1 -> L2", async () => {
    it("Send message from L1 to L2", async () => {
      hre.changeNetwork('ethGoerli');
      const message = '0xabcd'
      await fxStateRootTunnel.sendMessageToChild(ethers.utils.arrayify('0xABCD'))

      hre.changeNetwork('polygonMumbai');
      // This will be broken if test timed out, or test conditions are met.
      const startTime = new Date().getTime()
      while (true) {
        await new Promise(f => setTimeout(f, 5000));
        const latestData = await fxStateChildTunnel.latestData()
        if (latestData === message) {
          break;
        }
        const nowTime = new Date().getTime()
        console.log(`Still waiting for message to be propagated from L1 -> L2. Elapsed time: ${(nowTime - startTime) * 0.001}s`)
      }
    });
  });

  describe("L2 -> L1", async () => {
    it("Send message from L2 to L1", async () => {
      hre.changeNetwork('polygonMumbai');
      const message = '0xabcd'
      const sendMessageToRootTx = await fxStateChildTunnel.sendMessageToRoot(ethers.utils.arrayify(message))
      const sendMsgEventSig = '0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036'
      const url = `https://apis.matic.network/api/v1/mumbai/exit-payload/${sendMessageToRootTx.hash}?eventSignature=${sendMsgEventSig}`
      console.log(url)
      let proof: string = 'invalid-proof'
      const startTime = new Date().getTime()
      while (true) {
        await new Promise(f => setTimeout(f, 5000));
        type ResponseObj = {
          error: boolean
          message: string
          result: string
        }
        try {
          const resp = await axios.get<ResponseObj>(url);
          const proofObj = resp.data
          if ('result' in proofObj && !('error' in proofObj)) {
            proof = proofObj.result
            break
          }
        } catch(err) {
          if (!axios.isAxiosError(err)) {
            throw err
          }
        }
        const nowTime = new Date().getTime()
        console.log(`Still waiting for message to be checkpointed from L2 -> L1. Elapsed time: ${(nowTime - startTime) * 0.001}s`)
      }
      await fxStateRootTunnel.receiveMessage(ethers.utils.arrayify(proof))
      await new Promise(f => setTimeout(f, 60000));
      const latestData = await fxStateRootTunnel.latestData()
      expect(latestData).to.equal(message)
    });
  });
});
