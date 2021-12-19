import { JsonRpcProvider, TransactionReceipt, TransactionResponse } from '@ethersproject/providers';
import {Contract, ethers, Wallet } from 'ethers';
import { KeyValueStoreClient } from 'defender-kvstore-client';
import axios from 'axios';
require('dotenv').config();

const l1VaultABI = [
  "function lastTransferBlockNum() view returns(uint256)",
  "function lastTransferAmount() view returns(uint256)",
  "function lastClearedTransferBlockNum() view returns(uint256)",
  "function debtToL2() view returns(uint256)",
  "function lastClearedL2TransferBlockNum() view returns(uint256)",
  "function vaultTVL() view returns (uint256)",
  "function l2Rebalance()",
]
const l2VaultABI = [
  "function lastTransferBlockNum() view returns(uint256)",
  "function lastTransferAmount() view returns(uint256)",
  "function lastClearedTransferBlockNum() view returns(uint256)",
  "function lastClearedL1TransferBlockNum() view returns(uint256)",
  "function setL1TVL(uint256)",
  "function L1L2Rebalance()",
]
const contractRegistryABI = [
  "function getAddress(string) view returns(address)",
]
const l1StagingABI = [
  "function l1Exit(uint256, uint256, bytes)",
]
const l2StagingABI = [
  "function l2Withdraw(uint256)",
  "function l2ClearFund(uint256, uint256)",
]
const usdcABI = [
  "function balanceOf(address) view returns(uint256)"
]

const l1FxTunnelABI = [
  "function receiveMessage(bytes)"
]

async function tryTx(name: string, ptx: Promise<TransactionResponse>): Promise<string> {
  try {
    let tx = await ptx;
    await tx.wait();
    console.log(`Tx ${name} succeeded with tx-hash:`, tx.hash);
    return tx.hash;
  } catch (e) {
    console.log(`Tx ${name} failed with error:`, e);
    return undefined;
  }
}

export async function getProof(
  maticAPIUrl: string, 
  txHash: string,
  eventSig: string,
): Promise<string> {
  const url = `${maticAPIUrl}/exit-payload/${txHash}?eventSignature=${eventSig}`
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
    return undefined
  }
}

// Entrypoint for the Autotask
export async function handler(event: any) {
  console.log(event.isLocal ? 'Running in local Environment.' : 'Running in Autotask Environment.')
  const {
    mnemonic, 
    ethAlchemyURL, 
    polygonAlchemyURL,
    l1ContractRegistryAddress,
    l2ContractRegistryAddress,
  } = event.secrets;
  const goerliProvider: JsonRpcProvider = new ethers.providers.JsonRpcProvider(ethAlchemyURL);
  const mumbaiProvider: JsonRpcProvider = new ethers.providers.JsonRpcProvider(polygonAlchemyURL);

  const goerliWallet: Wallet = Wallet.fromMnemonic(mnemonic).connect(goerliProvider);
  const mumbaiWallet: Wallet = Wallet.fromMnemonic(mnemonic).connect(mumbaiProvider);

  console.log('Defender address:', goerliWallet.address);
  
  const l1ContractRegistry: Contract = new Contract(l1ContractRegistryAddress, contractRegistryABI, goerliWallet);
  const l2ContractRegistry: Contract = new Contract(l2ContractRegistryAddress, contractRegistryABI, mumbaiWallet);
  
  const l1Vault: Contract = new Contract(await l1ContractRegistry.getAddress('L1Vault'), l1VaultABI, goerliWallet);
  const l2Vault: Contract = new Contract(await l2ContractRegistry.getAddress('L2Vault'), l2VaultABI, mumbaiWallet);

  const l1USDC: Contract = new Contract(await l1ContractRegistry.getAddress('L1USDC'), usdcABI, goerliWallet);
  const l2USDC: Contract = new Contract(await l2ContractRegistry.getAddress('L2USDC'), usdcABI, mumbaiWallet);

  const l1Staging: Contract = new Contract(await l1ContractRegistry.getAddress('L1Staging'), l1StagingABI, goerliWallet);
  const l2Staging: Contract = new Contract(await l2ContractRegistry.getAddress('L2Staging'), l2StagingABI, mumbaiWallet);
  
  let l1VaultTVL = await l1Vault.vaultTVL();
  let l1LastClearedL2TransferBlockNum = await l1Vault.lastClearedL2TransferBlockNum();
  let l2LastClearedL1TransferBlockNum = await l2Vault.lastClearedL1TransferBlockNum();
  let l1LastClearedTransferBlockNum = await l1Vault.lastClearedTransferBlockNum();
  let l2LastClearedTransferBlockNum = await l2Vault.lastClearedTransferBlockNum();

  await tryTx("l2Vault.setL1TVL()", l2Vault.setL1TVL(l1VaultTVL));
  if (!l1LastClearedTransferBlockNum.eq(l2LastClearedL1TransferBlockNum)) {
    await tryTx(
      "l1Vault.setlastClearedTransferBlockNum()", 
      l1Vault.setlastClearedTransferBlockNum(l2LastClearedL1TransferBlockNum)
    );
  }
  if (!l2LastClearedTransferBlockNum.eq(l1LastClearedL2TransferBlockNum)) {
    await tryTx(
      "l2Vault.setlastClearedTransferBlockNum()", 
      l2Vault.setlastClearedTransferBlockNum(l1LastClearedL2TransferBlockNum)
    );
  }
  
  l1LastClearedTransferBlockNum = await l1Vault.lastClearedTransferBlockNum();
  l2LastClearedTransferBlockNum = await l2Vault.lastClearedTransferBlockNum();

  let l1LastTransferBlockNum = await l1Vault.lastTransferBlockNum();
  let l1VaultDebtToL2 = await l1Vault.debtToL2();
  // If there is debt and bridge is unlocked.
  if (!l1VaultDebtToL2.isZero() && l1LastTransferBlockNum.eq(l1LastClearedTransferBlockNum)) {
    await tryTx("l2Vault.l2Rebalance()", l2Vault.l2Rebalance());
  }
  
  // Clear fund in L2 stging contract if there is some USDC.
  const l2StagingUSDCBalance = await l2USDC.balanceOf(l2Staging.address);
  const l1LastTransferAmount = await l1Vault.lastTransferAmount();
  l1LastTransferBlockNum = await l1Vault.lastTransferBlockNum();
  if (l2StagingUSDCBalance.gte(l1LastTransferAmount) && !l1LastTransferAmount.isZero()) {
    await tryTx("l2Staging.l2ClearFund()", l2Staging.l2ClearFund(l1LastTransferBlockNum, l1LastTransferAmount));
  }

  let store = new KeyValueStoreClient(event.isLocal ? { path: './store.json' } : event);

  // Clear fund in L1 staging if USDC burn tx is checkpointed.
  const l2USDCBurnTxHash = await store.get(`${l1Vault.address}-usdc-burn-tx`);
  if (l2USDCBurnTxHash) {
    const proof = await getProof('https://apis.matic.network/api/v1/mumbai',
      l2USDCBurnTxHash,
      '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef', // ERC20 transfer event sig.
    );
    if (proof) {
      await tryTx(
        'l1Staging.l1Exit()',
        l1Staging.l1Exit(
          await l2Vault.lastTransferBlockNum(), 
          await l2Vault.lastTransferAmount(), 
          ethers.utils.arrayify(proof)
        )
      )
      store.del(`${l1Vault.address}-usdc-burn-tx`)
    }
  }
  // Relay message proof if checkpointed.
  const l2MessageBurnTxHash = await store.get(`${l1Vault.address}-message-burn-tx`);
  if (l2MessageBurnTxHash) {
    const proof = await getProof('https://apis.matic.network/api/v1/mumbai',
    l2MessageBurnTxHash,
      '0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036', // MSG event sig.
    );
    if (proof) {
      const l1FxTunnel: Contract = new Contract(
        await l1ContractRegistry.getAddress('L1FxTunnel'), 
        l1FxTunnelABI,
        goerliWallet,
      )
      await tryTx(
        'l1FxTunnel.receiveMessage()',
        l1FxTunnel.receiveMessage(ethers.utils.arrayify(proof))
      )
      store.del(`${l1Vault.address}-message-burn-tx`)
    }
  }
  // Trigger rebalance L1 <> L2.
  const txHash = await tryTx("l2Vault.L1L2Rebalance()", l2Vault.L1L2Rebalance());
  if (txHash) {
    const sendFundToL1Topic = ethers.utils.id("SendFundToL1(uint256)")
    const receiveFundFromL1Topic = ethers.utils.id("ReceiveFundFromL1(uint256)")
    const txr: TransactionReceipt = await mumbaiProvider.getTransactionReceipt(txHash);
    if (txr.logs.length) {
      if (sendFundToL1Topic in txr.logs[0].topics) {
        store.put(`${l1Vault.address}-usdc-burn-tx`, txHash);
      } else if (receiveFundFromL1Topic in txr.logs[0].topics) {
        store.put(`${l1Vault.address}-message-burn-tx`, txHash);
      }
    }
  }
}

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
  handler({ 
    secrets: { 
      ethAlchemyURL: process.env.ETH_ALCHEMY_URL,
      polygonAlchemyURL: process.env.POLYGON_ALCHEMY_URL,
      mnemonic: process.env.MNEMONIC,
      l1ContractRegistryAddress: process.env.L1_CONTRACT_REGISTRY,
      l2ContractRegistryAddress: process.env.L2_CONTRACT_REGISTRY,
    },
    isLocal: true,
  })
  .then(() => process.exit(0))
  .catch((error: Error) => { console.error(error); process.exit(1); });
}
