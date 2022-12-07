# Solidity API

  ###
  BaseStrategyTest
  >
  Test general functionalities of strategies.

      - `testSweep`
      Test only governance can sweep tokens from vaults.

  ###
  BaseVaultTest
  >
  Test general functionalities of vaults.

      - `testHarvest`
      Test harvesting strategies and makes sure locked profit works.
      - `testStrategyAddition`
      Test addition to new strategy works.
      - `testStrategyRemoval`
      Test removal of strategies work.
      - `testRemoveStrategyAndDivest`
      Test divesting of funds work after a strategy is removed
from withdrawal queue.
      - `testGetWithdrawalQueue`
      Test getter for withdrwal queue.
      - `testSetWithdrawalQueue`
      Test setter for withdrawal queue.
      - `testLiquidate`
      Test liquidating certain amount of assets from the
      - `testRebalance`
      Test internal rebalanceing of vault.
      - `testRebalanceWithSlippage`
      Test internal rebalanceing of vault when strategies incur slippage
while divesting from them.
      - `testUpdateStrategyAllocations`
      Test updating strategy allocation bps.
      - `testSetWormRouter`
      Test updating wormhole router. Only governance should be able to do it.
      - `testBridgeEscrow`
      Test updating bridge escrow contract. Only governance should be able to do it.

  ###
  L2BridgeEscrowTest
  >
  Test functionalities of l2 brige escrow contract.

      - `testwithdraw`
      Test that only l2 vault can withdraw a certain amount from
l2 bridge escrow.
      - `testclearFunds`
      Test that l2 wormhole router can clear funds l2 bridge escrow.
      - `testclearFundsInvariants`
      Test that only wormhole router can clear funds from l2 bridge escrow once
funds are received.

  ###
  L1BridgeEscrowTest
  >
  Test functionalities of l1 brige escrow contract.

      - `testclearFunds`
      Test that l1 wormhole router can clear funds l1 bridge escrow.
      - `testclearFundsInvariants`
      Test that only wormhole router can clear funds from l1 bridge escrow once
funds are received.
      - `testclearFundsWithBadProof`
      Test that attempting to clear funds with bad proof won&#x27;t work.

  ###
  ConvexStratTest
  >
  Test convex FRAX-USDC strategy

      - `testCanDeposit`
      Test depositing into strategy works.
      - `testCanSlip`
      Test slippage doesn&#x27;t incure error while claiming/selling rewards.
      - `testCanDivest`
      Test divesting from convex strategy works.
      - `testWithdrawFuzz`
      Fuzz test to make sure we are able to withdraw from convex strategy
in random scenarios.
      - `testRewards`
      Test claiming rewards work.
      - `testCanSellRewards`
      Test that selling reward token works.
      - `testTVLFuzz`
      Fuzz test of make sure that tvl calculation works in random scenarios.

  ###
  CurveStratTest
  >
  Test MIM-3CRV strategy.

      - `testCanMintLpTokens`
      Test lp tokens are minted upon depositing assets to curve strategy.
      - `testCanSlip`
      Test slippage doesn&#x27;t incure error while claiming/selling rewards.
      - `testCanDivest`
      Test that divesting from curve strategy works.
      - `testCanDivestFully`
      Test that divesting with amount more than the TVL will result
in divesting only TVL amount and not incur error.
      - `testWithdrawFuzz`
      Fuzz test to test withdrawal in random scenarios.
      - `testTVLFuzz`
      Fuzz test to test TVL in random scenarios.
      - `testCanClaimRewards`
      Test that claiming reward tokens work.
      - `testCanSellRewards`
      Test that selling reward tokens work.

  ###
  L1DeltaNeutralTest
  >
  Test SSLP Strategy with Sushiswap in L1.

  ###
  L2DeltaNeutralTest
  >
  Test SSLP Strategy with Sushiswap in L2.

  ###
  DeltaNeutralV3Test
  >
  Test SSLP Strategy with Uniswap V3 in polygon.

      - `testCreatePosition`
      Test that a position can be opened.
      - `testEndPosition`
      Test that a position can be ended.
      - `testTVL`
      Test TVL calculation.
      - `testDivest`
      Test that value can divest from this strategy.

  ###
  EmergencyWithdrawalQueueTest
  >
  Test functionalities of emergency withdrawal queue.

      - `testEnqueueSuccess`
      Test enqueueing into emergency withdrawal queue works.
      - `testOnlyVaultCanEnqueue`
      Test that only vault can enqueue into emergency withdrawal queue works.
      - `testCorreclyEnqueueReturningUser`
      Test that a user can have multiple requests in emergency withdrawal queue.
      - `testDequeueSuccess`
      Test that dequeueing from emergency withdrawal queue works.

  ###
  ForwardTest
  >
  Test the forwarder contract

      - `testDoubleDeposit`
      Test forwarding transactions in batch works.
      - `testTransactVaultAndBasket`
      Test forwarding works for both vaults and baskets.

  ###
  CompoundStratTest
  >
  Test compound strategy

      - `testStrategyInvest`
      Investing into strategy works.
      - `testStrategyMakesMoneyWithCOMPToken`
      Test strategy makes money with reward tokens.
      - `testStrategyMakesMoneyWithCToken`
      Test strategy makes money with lp tokens.
      - `testStrategyLosesMoneyWithCToken`
      Test strategy looses money with lp tokens, when price goes down.
      - `testDivestFromStrategy`
      Test divesting TVL amount from strategy works.
      - `testStrategyDivestsOnlyAmountNeeded`
      Test divesting certain amount less than TVL from strategy works.
      - `testDivestMoreThanTVL`
      Test attempting to divest an amount more than the TVL results in
divestment of the TVL amount.
      - `testDivestLessThanFloat`
      Test not selling lp token when there is enough assets to cover divestment.
      - `testCanInvestZero`
      Test investing a zero amount doesn&#x27;t cause error.
      - `testCanSellRewards`
      Test selling reward token works.

  ###
  L1VaultTest
  >
  Test L1 vault specific functionalities.

      - `testSendTVL`
      Test sending TVL to L2 works.
      - `testprocessFundRequest`
      Test processing fund request from L2 works.
      - `testafterReceive`
      Test callback after receiving funds in bridge escrow works.
      - `testLockedProfit`
      Test that profit is locked over a &#x60;LOCK_INTERVAL&#x60;.

  ###
  AAVEStratTest
  >
  Test AAVE strategy

      - `testStrategyMakesMoney`
      Test strategy makes money over time.
      - `testStrategyDivestsOnlyAmountNeeded`
      Test divesting a certain amount works.
      - `testDivestMoreThanTVL`
      Test attempting to divest an amount more than the TVL results in
divestment of the TVL amount.
      - `testDivestLessThanFloat`
      Test not selling lp token when there is enough assets to cover divestment.
      - `testCanInvestZero`
      Test investing a zero amount doesn&#x27;t cause error.
      - `testTVL`
      Test TVL calculation.

  ###
  L2VaultTest
  >
  Test functionalities of L2 vault.

      - `testDeploy`
      Test post deployment, initial state of the vault.
      - `testDepositRedeem`
      Test redeeming after deposit.
      - `testDepositWithdraw`
      Test withdawing after deposit.
      - `testMint`
      Test minting vault token.
      - `testMinDeposit`
      Test minting zero share results in error.
      - `testDepositNoStrategyInvest`
      Test that depositing doesn&#x27;t result in funds being invested into
      - `testMintNoStrategyInvest`
      Test that minting doesn&#x27;t result in funds being invested into
      - `testManagementFee`
      Test management fee is deducted and transferred to governance address.
      - `testLockedProfit`
      Test profit is locked over the &#x60;LOCK_INTERVAL&#x60; period.
      - `testReceiveTVL`
      Test that L2 vault can receive TVL from L1 vault.
      - `testLockedTVL`
      Test that locked profit implies tvl being locked over &#x60;LOCK_INTERVAL&#x60;
duration.
      - `testL1ToL2Rebalance`
      Test that correct rebalance decition is taken once L1 TVL is received by the L2 vault,
and there is a need to rebalance in L1 -&gt; L2 direction.
      - `testL1ToL2RebalanceWithEmergencyWithdrawalQueueDebt`
      Test that correct amount is requested from L1 while rebalancing, when there is
outstanding emergenct withdrawal queue debt.
      - `testL2ToL1Rebalance`
      Test that correct rebalance decition is taken once L1 TVL is received by the L2 vault,
and there is a need to rebalance in L2 -&gt; L1 direction.
      - `testL2ToL1RebalanceWithEmergencyWithdrawalQueueDebt`
      Test that correct amount is transfeeed from L2 while rebalancing, when there is
outstanding emergenct withdrawal queue debt.
      - `testWithdrawalFee`
      Test that withdrawal fee is deducted while withdwaring.
      - `testSettingFees`
      Test that goveranance can modify management fees.
      - `testVaultPause`
      Test that goveranance can pause the vault.
      - `testEmergencyWithdrawal`
      Test emergency withdrawal queue enqueue happens when there is not enough assets in the L2 vault
to process the withdrawal request.
      - `testEmergencyWithdrawalWithRedeem`
      Test emergency withdrawal queue enqueue happens when there is not enough assets in the L2 vault
to process the redeem request.
      - `testEwqDebt`
      Test that debt to emergency withdrawal queue is calculated correctly.
      - `testEwqWithdraw`
      Test dequeueing from emergency withdrawal queue works when funds are available
in the vault, if enqueue happened via withdraw request.
      - `testEwqRedeem`
      Test dequeueing from emergency withdrawal queue works when funds are available
in the vault, if enqueue happened via redeem request.
      - `testEwqMinWithdraw`
      Test that emergency withdrawal queue enqueue is rejected if user
is depositing an amount less the &#x60;vault.ewqMinAssets&#x60; usdc.
      - `testDetailedPrice`
      Test that view functions for detailed price of vault token works.
      - `testSettingForwarder`
      Test that governance can modify forwarder address.
      - `testSetEwq`
      Test that governance can modify emergency withdrawal queue address.
      - `testSettingRebalanceDelta`
      Test that governance can modify rebalance delta variable.

  ###
  RouterTest
  >
  Test functionalities of the router contract.

      - `testMultipleDeposits`
      Test that the router contract can handle multiple deposits.

  ###
  BtcEthBasketTest
  >
  Test two asset basket functionalities.

      - `testDepositWithdraw`
      Test depositing and withdrawing form the basket works.
      - `testRedeem`
      Test redeeming form the basket works.
      - `testMaxWithdraw`
      Test withdrawing max amount works.
      - `testDepositSlippage`
      Test that slippage parameter while depositing works.
      - `testWithdrawSlippage`
      Test that slippage parameter while withdrawing works.
      - `testRedeemSlippage`
      Test that slippage parameter while redeeming works.
      - `testBuySplitsFuzz`
      Fuzz test for selling when there is random imbalance in BTC and ETH balanace.
      - `testBuySplits`
      Test buying when there is imbalance in BTC and ETH balanace
      - `testSellSplits`
      Test selling when there is imbalance in BTC and ETH balanace.
      - `testVaultPause`
      Test that pausing the basket works.
      - `testDetailedPrice`
      Test view functions for detailed prices.

  ###
  L2WormholeRouterTest
  >
  Test L2 wormhole router functinoalities.

      - `testWormholeConfigUpdates`
      Test that the governance can update wormhole router
configurations.
      - `testTransferReport`
      Test that the L2 wormhole router sends message to L1 after funds are transferred
to L2.
      - `testMessageValidation`
      Test that the message vailidation works.
      - `testRequestFunds`
      Test that, the L2 wormhole router requests funds from L1 in correct
message format.
      - `testReceiveFunds`
      Test that, the L2 wormhole router can receive funds sent by L1 vault.
      - `testReceiveFundsInvariants`
      Test that old messages are not received by the wormhole router.
      - `testReceiveTVL`
      Test that, the L2 wormhole router can receive TVL sent by L1 vault.

  ###
  L1WormholeRouterTest
  >
  Test L1 wormhole router functinoalities.

      - `testReportTVL`
      Test router reports TVL to L2 in correct format.
      - `testreportFundTransfer`
      Test that the wormhole router sends message after funds are transferred
to L2.
      - `testReceiveFunds`
      Test receiving funds from L2 works.
      - `testReceiveFundRequest`
      Test receiving fund request from L2.

