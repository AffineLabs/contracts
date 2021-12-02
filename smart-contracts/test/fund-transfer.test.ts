import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import hre from "hardhat";
import { assert } from 'console';
import { Contract, ContractTransaction } from 'ethers';
import usdcABI from './assets/usdc-abi.json';
import { getTxExplorerLink } from "../utils/bc-explorer-links";
import axios from "axios";
import { AllContracts, deployAll } from "../scripts/utils/deploy-all";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const ETH_NETWORK_NAME = 'ethGoerli'
const POLYGON_NETOWRK_NAME = 'polygonMumbai'

const CHECKPOINT_MANAGER = process.env.CHECKPOINT_MANAGER || "";
const FX_ROOT = process.env.FX_ROOT || "";
const FX_CHILD = process.env.FX_CHILD || "";
const ETH_USDC = process.env.ETH_USDC || "";
const POLYGON_USDC = process.env.POLYGON_USDC || "";
const POLYGON_ERC20_PREDICATE = process.env.POLYGON_ERC20_PREDICATE || "";
const ROOT_CHAIN_MANAGER = process.env.ROOT_CHAIN_MANAGER || "";

assert(CHECKPOINT_MANAGER !== "", "Checkpint Manager address must not be empty. Please set CHECKPOINT_MANAGER in the .env file.");
assert(FX_ROOT !== "", "Fx root address must not be empty. Please set FX_ROOT in the .env file.");
assert(FX_CHILD !== "", "Fx child address must not be empty. Please set FX_CHILD in the .env file.");
assert(ETH_USDC !== "", "ETH USDC Address is needed for testing. Please set ETH_USDC in the .env file.");
assert(POLYGON_USDC !== "", "Polygon USDC Address is needed for testing. Please set POLYGON_USDC in the .env file.");
assert(POLYGON_ERC20_PREDICATE !== "", "Polygon ERC20 predicate address is needed for testing. Please set POLYGON_ERC20_PREDICATE in the .env file.");
assert(ROOT_CHAIN_MANAGER !== "", "POS Portal RootChainManager address is needed for testing. Please set ROOT_CHAIN_MANAGER in the .env file.");

chai.use(solidity);
const { expect } = chai;

async function getL2MessageProof(txHash: string): Promise<string> {
  const sendMsgEventSig = '0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036'
  const url = `https://apis.matic.network/api/v1/mumbai/exit-payload/${txHash}?eventSignature=${sendMsgEventSig}`
  console.log(`Waiting for message proof by polling URL: ${url}\n`)
  const startTime = new Date().getTime()
  while (true) {
    await new Promise(f => setTimeout(f, 60000));
    type MaticAPIResponse = {
      error: boolean
      message: string
      result: string
    }
    try {
      const resp = await axios.get<MaticAPIResponse>(url);
      const proofObj = resp.data
      if ('result' in proofObj && !('error' in proofObj)) {
        return proofObj.result
      }
    } catch(err) {
      if (!axios.isAxiosError(err)) {
        throw err
      }
    }
    const nowTime = new Date().getTime()
    console.log(`Still waiting for message to be checkpointed from L2 -> L1. Elapsed time: ${(nowTime - startTime) * 0.001}s`)
  }
}

async function waitForNonZeroL2StagingBalance(l2Staging: Contract) {
  hre.changeNetwork(POLYGON_NETOWRK_NAME);
  const polygonUSDCContract: Contract = new ethers.Contract(POLYGON_USDC, usdcABI, ethers.provider.getSigner());
  const startTime = new Date().getTime()
  while (true) {
    await new Promise(f => setTimeout(f, 60000));
    const stagingBalance = await polygonUSDCContract.balanceOf(l2Staging.address);
    if (stagingBalance > 0) {
      break;
    }
    const nowTime = new Date().getTime()
    console.log(`Still waiting for fund to be reflected in L2 Staging contract. Elapsed time: ${(nowTime - startTime) * 0.001}s`)
  }
}

describe("Eth-Matic Fund Transfer Integration Test", () => {
  let l1Vault: Contract;
  let l2Vault: Contract;
  let l2Staging: Contract;
  let l1FxTunnel: Contract;

  // Runs once before running all tests.
  before(async() => {
    const [governance, defender] = await ethers.getSigners()
    const allContracts: AllContracts = await deployAll(
      governance,
      defender,
      ETH_NETWORK_NAME,
      POLYGON_NETOWRK_NAME,
      CHECKPOINT_MANAGER,
      ROOT_CHAIN_MANAGER,
      ETH_USDC,
      FX_ROOT,
      POLYGON_USDC,
      POLYGON_ERC20_PREDICATE,
      FX_CHILD,
    )

    l1Vault = allContracts.vaultContracts.L1VaultContract;
    l2Vault = allContracts.vaultContracts.L2VaultContract;
    l2Staging = allContracts.stagingContract.L2StagingContract;
    l1FxTunnel = allContracts.fxTunnelContracts.L1FxTunnel;
  });

  // Runs before each test.
  beforeEach(async () => {});

  describe("L1 -> L2", async () => {
    it("Send fund from L1 to L2", async () => {
        const initialL1TVL = ethers.utils.parseUnits('0.001', 6);

        hre.changeNetwork(ETH_NETWORK_NAME);
        let [governance, defender] = await ethers.getSigners()
        // Transfer some USDC from owner to L1 vault.
        const ethUSDCContract: Contract = new ethers.Contract(ETH_USDC, usdcABI, ethers.provider.getSigner());
        let tx: ContractTransaction = await ethUSDCContract.transfer(l1Vault.address, initialL1TVL);
        await tx.wait();
        expect(await ethUSDCContract.balanceOf(l1Vault.address)).to.eq(initialL1TVL);

        // Get L1 TVL from L1 Vault.
        const currentL1TVL = await l1Vault.vaultTVL();
        expect(currentL1TVL).to.eq(initialL1TVL);

        hre.changeNetwork(POLYGON_NETOWRK_NAME);
        [governance, defender] = await ethers.getSigners()
        console.log('Setting L1 TVL in L2 Vault.')
        tx = await l2Vault.connect(defender).setL1TVL(currentL1TVL);
        await tx.wait();
        console.log(` > tx: ${getTxExplorerLink(POLYGON_NETOWRK_NAME, tx)}`);

        console.log('Trigger of rebalance in L2 Vault.')
        tx = await l2Vault.connect(defender).L1L2Rebalance();
        await tx.wait();
        console.log(` > tx: ${getTxExplorerLink(POLYGON_NETOWRK_NAME, tx)}`);

        const fxChildTxHash = tx.hash;
        const messageProof = await getL2MessageProof(fxChildTxHash);

        hre.changeNetwork(ETH_NETWORK_NAME);
        [governance, defender] = await ethers.getSigners()
        console.log('Record debt amount in L1 Vault by presending L2 Vault message proof.')
        tx = await l1FxTunnel.connect(defender).receiveMessage(ethers.utils.arrayify(messageProof));
        await tx.wait();
        console.log(` > tx: ${getTxExplorerLink(ETH_NETWORK_NAME, tx)}`);

        console.log('L1 debt to L2', await l1Vault.debtToL2());
        expect(await l1Vault.debtToL2()).to.eq(initialL1TVL.div(10));

        console.log('Initiate transfer of L1 debt to L2.')
        tx = await l1Vault.connect(defender).l2Rebalance();
        await tx.wait();
        console.log(` > tx: ${getTxExplorerLink(ETH_NETWORK_NAME, tx)}`);

        console.log('L2 debt to L1', await l1Vault.vaultTVL());
        expect(await l1Vault.vaultTVL()).to.eq(initialL1TVL.div(10).mul(9));

        await waitForNonZeroL2StagingBalance(l2Staging);

        const l1VaultLastTransferBlockNum = await l1Vault.lastTransferBlockNum();
        const l1VaultLastTransferAmound = await l1Vault.lastTransferAmount();

        hre.changeNetwork(POLYGON_NETOWRK_NAME);
        [governance, defender] = await ethers.getSigners()
        console.log('Clearing fund in L2 staging contract');
        tx = await l2Staging.connect(defender).clearFund(l1VaultLastTransferBlockNum, l1VaultLastTransferAmound, {gasPrice: ethers.utils.parseUnits('1', 'gwei'), gasLimit: 2500000})
        await tx.wait();
        console.log(` > tx: ${getTxExplorerLink(POLYGON_NETOWRK_NAME, tx)}`);

        expect(await l2Vault.vaultTVL()).to.eq(initialL1TVL.div(10));
    });
  });
});
