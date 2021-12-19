import chai from "chai";
import hre from "hardhat";
import usdcABI from './assets/usdc-abi.json';
import rootChainManagerABI from './assets/root-chain-manager.json';

import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { config } from "../utils/config";
import { BigNumber, Contract, ContractTransaction } from 'ethers';
import { getTxExplorerLink } from "../utils/bc-explorer-links";
import { AllContracts, deployAll } from "../scripts/utils/deploy-all";
import { waitForL2MessageProof, waitForNonZeroAddressTokenBalance } from "./utils/wait-utils";

const ETH_NETWORK_NAME = 'ethGoerli'
const POLYGON_NETOWRK_NAME = 'polygonMumbai'

chai.use(solidity);
const { expect } = chai;

it("Eth-Matic Fund Transfer Integration Test L2 -> L1", async () => {
  let l1Vault: Contract;
  let l2Vault: Contract;
  let l1Staging: Contract;

  let [governance, defender] = await ethers.getSigners()
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
  )

  l1Vault = allContracts.vaultContracts.L1VaultContract;
  l2Vault = allContracts.vaultContracts.L2VaultContract;
  l1Staging = allContracts.stagingContract.L1StagingContract;

  const initialL2TVL = ethers.utils.parseUnits('0.001', 6);

  hre.changeNetwork(POLYGON_NETOWRK_NAME);
  [governance, defender] = await ethers.getSigners()
  const polygonUSDCContract: Contract = new ethers.Contract(config.l2USDC, usdcABI, governance);
  const l2GovernanceBalance: BigNumber = await polygonUSDCContract.balanceOf(governance.address);
  console.log('Balance of L2 governance address:', l2GovernanceBalance.toString())

  let tx: ContractTransaction;
  if (l2GovernanceBalance.isZero()) {
    hre.changeNetwork(ETH_NETWORK_NAME);
    [governance, defender] = await ethers.getSigners()
    const rootChainManagerContract: Contract = new ethers.Contract(config.l1ChainManager, rootChainManagerABI, governance);
    const amount = ethers.utils.defaultAbiCoder.encode(['uint256'], [ethers.utils.parseUnits('1', 6)])
    const ethUSDCContract: Contract = new ethers.Contract(config.l1USDC, usdcABI, governance);
    // Approve tokens to ERC20 Predicate.
    tx = await ethUSDCContract.approve(config.l2ERC20Predicate, amount);
    await tx.wait();
    // Deposit 
    tx = await rootChainManagerContract.depositFor(
      governance.address, 
      config.l1USDC, 
      ethers.utils.arrayify(amount),
      {gasPrice: ethers.utils.parseUnits('1', 'gwei'), gasLimit: 2500000}
    )
    await tx.wait();
    console.log(` > tx: ${getTxExplorerLink(ETH_NETWORK_NAME, tx)}`);
  }

  await waitForNonZeroAddressTokenBalance(
    POLYGON_NETOWRK_NAME, 
    config.l2USDC,
    usdcABI, 
    'Governance', 
    governance.address
  );
  
  hre.changeNetwork(POLYGON_NETOWRK_NAME);
  [governance, defender] = await ethers.getSigners()

  console.log('Transfer some USDC from owner to L2 vault.')
  tx = await polygonUSDCContract.transfer(l2Vault.address, initialL2TVL);
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(ETH_NETWORK_NAME, tx)}`);

  // Get L1 TVL from L1 Vault.
  const currentL2TVL = await l2Vault.vaultTVL();
  expect(currentL2TVL).to.eq(initialL2TVL);

  console.log('Trigger of rebalance in L2 Vault.')
  tx = await l2Vault.connect(defender).L1L2Rebalance();
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(POLYGON_NETOWRK_NAME, tx)}`);

  const fxChildTxHash = tx.hash;
  const messageProof = await waitForL2MessageProof(
    'https://apis.matic.network/api/v1/mumbai',
    fxChildTxHash,
    '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef', // ERC20 transfer event sig.
  );

  hre.changeNetwork(ETH_NETWORK_NAME);
  [governance, defender] = await ethers.getSigners()
  const l2VaultLastTransferBlockNum = await l2Vault.lastTransferBlockNum();
  const l2VaultLastTransferAmount = await l2Vault.lastTransferAmount();

  console.log(`Calling exit fund in L1 staging contract with params: (${l2VaultLastTransferBlockNum}, ${l2VaultLastTransferAmount})`)
  tx = await l1Staging.connect(defender).l1Exit(
    l2VaultLastTransferBlockNum, 
    l2VaultLastTransferAmount, 
    ethers.utils.arrayify(messageProof),
    {gasPrice: ethers.utils.parseUnits('1', 'gwei'), gasLimit: 500000} 
  );
  await tx.wait();
  console.log(` > tx: ${getTxExplorerLink(ETH_NETWORK_NAME, tx)}`);

  const ethUSDCContract: Contract = new ethers.Contract(config.l1USDC, usdcABI, governance);
  expect(await l1Vault.vaultTVL()).to.eq(initialL2TVL.mul(90).div(100));
});
