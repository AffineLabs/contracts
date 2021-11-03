// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "./IStrategy.sol";

contract L2Vault is ERC20 {
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

    // TVL of L1 denominated in `token` (e.g. USDC). This value will be updated by oracle.
    uint256 public L1TotalLockedValue;

    uint256 public constant MAX_STRATEGIES = 10;
    address[MAX_STRATEGIES] public withdrawalQueue;
    struct strategyInfo {
        uint256 activation;
        uint256 debtRatio;
        uint256 minDebtPerHarvest;
        uint256 maxDebtPerHarvest;
        uint256 lastReport;
        uint256 totalDebt;
        uint256 totalGain;
        uint256 totalLoss;
    }
    // Strategy contract address to its current info
    mapping(address => strategyInfo) strategies;
    event StrategyAdded(
        address indexed strategy,
        uint256 debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest
    );
    event StrategyRemoved(address indexed strategy);

    // debtRatio is always less than MAX_BPS
    uint256 debtRatio;
    uint256 public totalDebt;
    uint256 constant MAX_BPS = 10000;

    // TODO: do we still need this?
    address public chainlinkClient;

    // TODO: Add some events here. Actually log events as well

    constructor(address governance_, address token_)
        ERC20("Alpine Save", "AlpSave")
    {
        governance = governance_;
        token = token_;
    }

    // We don't need to check if user == msg.sender()
    // So long as this conract can transfer usdc from the given user, everything is fine
    function deposit(address user, uint256 amountToken) external {
        // transfer usdc to this contract
        IERC20 Token = IERC20(token);
        Token.transferFrom(user, address(this), amountToken);

        // mint
        _issueSharesForAmount(user, amountToken);
    }

    function _issueSharesForAmount(address user, uint256 amountToken) internal {
        uint256 numShares;
        uint256 totalTokens = totalSupply();
        if (totalTokens == 0) {
            numShares = amountToken;
        } else {
            numShares = (amountToken * totalTokens) / globalTVL();
        }
        _mint(user, numShares);
    }

    // TVL is denominated in `token`.
    function globalTVL() public view returns (uint256) {
        // Get tvl of this vault
        uint256 vaultAssets = IERC20(token).balanceOf(address(this)) +
            totalDebt;
        return vaultAssets + L1TotalLockedValue;
    }

    // TODO: Assuming a chainlink node will call this. Restrict apporiately once design is more clear
    function setL1TVL(uint256 l1TVL) external {
        L1TotalLockedValue = l1TVL;
    }

    // TODO: handle access control, re-entrancy
    function withdraw(address user, uint256 shares) external {
        require(
            shares <= balanceOf(user),
            "Cannot burn more shares than owned"
        );

        uint256 valueOfShares = _getShareValue(shares);

        // TODO: handle case where the user is trying to withdraw more value than actually exist in the vault
        if (valueOfShares > IERC20(token).balanceOf(address(this))) {}

        // burn
        _burn(user, shares);

        // transfer usdc out
        IERC20 Token = IERC20(token);
        Token.transferFrom(address(this), user, valueOfShares);
    }

    function _getShareValue(uint256 shares) internal view returns (uint256) {
        // The price of the vault share (e.g. alpSave).
        // This is a ratio of share/token, i.e. the numbers of shares for single wei of the input token

        uint256 totalShares = totalSupply();
        if (totalShares == 0) {
            return shares;
        } else {
            return shares * (globalTVL() / totalShares);
        }
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
            strategies[strategy].activation > 0,
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
        strategies[strategy] = strategyInfo({
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

    // This function will be called by a strategy in order to update totalDebt;
    function report() external {}

    // Compute rebalance params
    function computeL1L2Rebalance() internal {}

    // Rebalance strategies on this chain (L2)
    function computeRebalance() internal {}

    // This function fetches the NAV of the vault token from the chainlink client
    function getNAVofVaultToken() internal {}
}
