// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./IStrategy.sol";

contract BaseVault is ERC20 {
    // The address of token we'll take as input to the vault, e.g. USDC
    address public token;

    address public governance;
    modifier onlyGovernance() {
        require(
            msg.sender == governance,
            "Only Governance can call this function"
        );
        _;
    }
    uint256 public constant MAX_STRATEGIES = 10;
    address[MAX_STRATEGIES] public withdrawalQueue;
    struct StrategyInfo {
        uint256 activation;
        uint256 debtRatio;
        uint256 minDebtPerHarvest;
        uint256 maxDebtPerHarvest;
        uint256 lastReport;
        uint256 totalDebt;
        uint256 totalGain;
        uint256 totalLoss;
    }
    // All strategy information
    mapping(address => StrategyInfo) strategies;
    event StrategyAdded(
        address indexed strategy,
        uint256 debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest
    );
    event StrategyRemoved(address indexed strategy);
    event StrategyUpdateDebtRatio(address indexed strategy, uint256 debtRatio);
    event StrategyReported(
        address indexed strategy,
        uint256 gain,
        uint256 loss,
        uint256 debtPaid,
        uint256 totalGain,
        uint256 totalLoss,
        uint256 totalDebt,
        uint256 debtAdded,
        uint256 debtRatio
    );

    // debtRatio is always less than MAX_BPS
    uint256 debtRatio;
    // Total amount that the vault can get back from strategies (ignoring slippage)
    uint256 public totalDebt;
    uint256 constant MAX_BPS = 10000;
    uint256 constant SECS_PER_YEAR = 31_556_952;
    uint256 lastReport;

    // TODO: Add some events here. Actually log events as well

    constructor(address governance_, address token_)
        ERC20("Alpine Save", "AlpSave")
    {
        governance = governance_;
        token = token_;
        lastReport = block.timestamp;
    }

    function vaultTVL() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this)) + totalDebt;
    }

    function addStrategy(
        address strategy,
        uint256 debtRatio_,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest
    ) external onlyGovernance {
        // Check if queue is full. If it's not, the last element will be unset
        require(
            withdrawalQueue[MAX_STRATEGIES - 1] == address(0),
            "Vault has hit strategy limit"
        );

        // Check if this strategy can be activated
        require(strategy != address(0), "Strategy must be not be zero account");
        require(
            strategies[strategy].activation == 0,
            "Strategy must not already be active"
        );
        require(
            IStrategy(strategy).vault() == address(this),
            "Strategy must use this vault"
        );
        require(
            token == IStrategy(strategy).want(),
            "Strategy must take profits in token"
        );

        // Check if sanity properties violate invariants
        require(
            debtRatio + debtRatio_ <= MAX_BPS,
            "Debt cannot exceed 10k bps"
        );
        require(
            minDebtPerHarvest <= maxDebtPerHarvest,
            "minDebtPerHarvest must not exceed max"
        );

        // Actually add strategy
        strategies[strategy] = StrategyInfo({
            activation: block.timestamp,
            debtRatio: debtRatio_,
            minDebtPerHarvest: minDebtPerHarvest,
            maxDebtPerHarvest: minDebtPerHarvest,
            lastReport: block.timestamp,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0
        });
        emit StrategyAdded(
            strategy,
            debtRatio,
            minDebtPerHarvest,
            maxDebtPerHarvest
        );

        // The total amount of token that could be borrowed is now larger
        debtRatio += debtRatio_;

        //  Add strategy to withdrawal queue and organize
        withdrawalQueue[MAX_STRATEGIES - 1] = strategy;
        _organizeWithdrawalQueue();
    }

    function _organizeWithdrawalQueue() internal {
        // Reorganize `withdrawalQueue`.
        // If there is an
        // empty value between two actual values, then the empty value should be
        // replaced by the later value.
        //  NOTE: Relative ordering of non-zero values is maintained.

        // number or empty values we've seen iterating from left to right
        uint256 offset;

        for (uint256 i = 0; i < MAX_STRATEGIES; i++) {
            address strategy = withdrawalQueue[i];
            if (strategy == address(0)) offset += 1;
            else if (offset > 0) {
                // idx of first empty value seen takes on value of `strategy`
                withdrawalQueue[i - offset] = strategy;
                withdrawalQueue[i] = address(0);
            }
        }
    }

    function removeStrategy(address strategy) external {
        // Let governance/strategy remove the strategy
        require(
            msg.sender == strategy || msg.sender == governance,
            "Only goverance or the strategy can call"
        );
        if (strategies[strategy].debtRatio == 0) return;
        _removeStrategy(strategy);
    }

    function _removeStrategy(address strategy) internal {
        debtRatio -= strategies[strategy].debtRatio;
        strategies[strategy].debtRatio = 0;
        emit StrategyRemoved(strategy);
    }

    function updateStrategyDebtRatio(address strategy, uint256 debtRatio_)
        external
        onlyGovernance
    {
        require(strategies[strategy].activation > 0, "Strategy must be active");
        debtRatio -= strategies[strategy].debtRatio;
        strategies[strategy].debtRatio = debtRatio_;
        debtRatio += debtRatio_;
        require(debtRatio <= MAX_BPS, "debtRatio may not exceed MAX_BPS");
        emit StrategyUpdateDebtRatio(strategy, debtRatio_);
    }

    function updateManyStrategyDebtRatios(
        address[] calldata strategies_,
        uint256[] calldata debtRatios
    ) external onlyGovernance {
        for (uint256 i = 0; i < strategies_.length; i++) {
            address strategy = strategies_[i];
            uint256 newDebtRatio = debtRatios[i];
            require(
                strategies[strategy].activation > 0,
                "Strategy must be active"
            );
            debtRatio =
                debtRatio -
                strategies[strategy].debtRatio +
                newDebtRatio;
            strategies[strategy].debtRatio = newDebtRatio;
        }
        require(debtRatio <= MAX_BPS, "debtRatio may not exceed MAX_BPS");
    }

    // This function will be called by a strategy in order to update totalDebt;
    function report(
        uint256 gain,
        uint256 loss,
        uint256 debtPayment
    ) external returns (uint256) {
        require(
            strategies[msg.sender].activation > 0,
            "Strategy must be active"
        );
        // TODO: consider health check
        address strategy = msg.sender;

        // Strategy must be able to pay (gain + debtPayment) of token
        require(IERC20(token).balanceOf(strategy) >= gain + debtPayment);

        if (loss > 0) _reportLoss(strategy, loss);

        strategies[strategy].totalGain += gain;

        // Compute the line of credit the Vault is able to offer the Strategy (if any)
        uint256 credit = _creditAvailable(strategy);

        // # Amount that strategy has exceeded its debt limit
        // NOTE: debt <= StrategyInfo.totalDebt
        uint256 debt = _debtOutstanding(strategy);
        debtPayment = debtPayment < debt ? debtPayment : debt;

        // Update the actual debt based on the full credit we are extending to the Strategy
        // or the amount we are taking from the strategy
        // NOTE: At least one of `credit` or `debt` is always 0 (both can be 0)
        if (debtPayment > 0) {
            strategies[strategy].totalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }
        if (credit > 0) {
            strategies[strategy].totalDebt += credit;
            totalDebt += credit;
        }

        // Give/take balance to Strategy, based on the difference between the reported gains,
        //  debt payment, debt,  and the credit increase we are offering
        // NOTE: This is just used to adjust the balance of tokens between the Strategy and
        // the Vault based on the Strategy's debt limit (as well as the Vault's).

        uint256 totalAvail = gain + debtPayment;
        // Credit surplus, give to Strategy
        if (totalAvail < credit)
            IERC20(token).transfer(strategy, credit - totalAvail);
        // Credit deficit, take from Strategy
        if (totalAvail > credit)
            IERC20(token).transferFrom(
                strategy,
                address(this),
                totalAvail - credit
            );

        // Update report times
        _assessFees(block.timestamp);
        strategies[strategy].lastReport = block.timestamp;
        lastReport = block.timestamp;

        emit StrategyReported(
            strategy,
            gain,
            loss,
            debtPayment,
            strategies[strategy].totalGain,
            strategies[strategy].totalLoss,
            strategies[strategy].totalDebt,
            credit,
            strategies[strategy].debtRatio
        );

        // If the strategy has been removed, it owes the vault all of its assets
        if (strategies[strategy].debtRatio == 0)
            return IStrategy(strategy).estimatedTotalAssets();
        return debt;
    }

    function _reportLoss(address strategy, uint256 loss) internal {}

    function _creditAvailable(address strategy)
        internal
        view
        returns (uint256)
    {}

    function _debtOutstanding(address strategy)
        internal
        view
        returns (uint256)
    {}

    function _assessFees(uint256 currentBlock) internal virtual {}

    // Rebalance strategies on this chain (L2). No need for now. We can simply update strategy debtRatios
    function rebalance() external onlyGovernance {}
}
