// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AffineVault} from "src/vaults/AffineVault.sol";
import {BaseStrategy as Strategy} from "src/strategies/BaseStrategy.sol";
import {uncheckedInc} from "src/libs/Unchecked.sol";

contract RebalanceModule {

    uint256 constant MAX_BPS = 10_000;
    uint8 constant MAX_STRATEGIES = 20;

     /**
     * @notice Emitted when we do a strategy rebalance, i.e. when we make the strategy tvls match their tvl bps
     * @param caller The caller
     */
    event Rebalance(address indexed caller);


    function rebalance() external {
        AffineVault vault = AffineVault(msg.sender);
        ERC20 _asset = ERC20(vault.asset());

        uint256 tvl = vault.vaultTVL();

        // Loop through all strategies. Divesting from those whose tvl is too high,
        // Invest in those whose tvl is too low
        uint256[MAX_STRATEGIES] memory amountsToInvest;

        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            Strategy strategy = vault.withdrawalQueue(i);
            if (address(strategy) == address(0)) {
                break;
            }

            (, uint16 tvlBps, ) = vault.strategies(strategy);
            uint256 idealStrategyTVL = (tvl * tvlBps) / MAX_BPS;
            uint256 currStrategyTVL = strategy.totalLockedValue();
            if (idealStrategyTVL < currStrategyTVL) {
               vault.withdrawFromStrategy(strategy, currStrategyTVL - idealStrategyTVL);
            }
            if (idealStrategyTVL > currStrategyTVL) {
                amountsToInvest[i] = idealStrategyTVL - currStrategyTVL;
            }
        }

        // Loop through the strategies to invest in, and invest in them
        for (uint256 i = 0; i < MAX_STRATEGIES; i = uncheckedInc(i)) {
            uint256 amountToInvest = amountsToInvest[i];
            if (amountToInvest == 0) {
                continue;
            }

            // We aren't guaranteed that the vault has `amountToInvest` since there can be slippage
            // when divesting from strategies
            // NOTE: Strategies closer to the start of the queue are more likely to get the exact
            // amount of money needed
            amountToInvest = Math.min(amountToInvest, _asset.balanceOf(address(this)));
            if (amountToInvest == 0) {
                break;
            }
            // Deposit into strategy, making sure to not count this investment as a profit
            vault.depositIntoStrategy(vault.withdrawalQueue(i), amountToInvest);
        }

        emit Rebalance(msg.sender);
    }
}