// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseRelayRecipient} from "@opengsn/contracts/src/BaseRelayRecipient.sol";

import {BaseVault} from "../BaseVault.sol";
import {L2BridgeEscrow} from "./L2BridgeEscrow.sol";
import {DetailedShare} from "./Detailed.sol";
import {L2WormholeRouter} from "./L2WormholeRouter.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {EmergencyWithdrawalQueue} from "./EmergencyWithdrawalQueue.sol";

/**
 * @notice An L2 vault. This is a cross-chain vault, i.e. some funds deposited here will be moved to L1 for investment.
 * @dev This vault is ERC4626 compliant. See the EIP description here: https://eips.ethereum.org/EIPS/eip-4626.
 * @author Alpine Devs. Inspired by OpenZeppelin and Rari-Capital.
 */
contract L2Vault is
    ERC20Upgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    BaseVault,
    BaseRelayRecipient,
    DetailedShare,
    IERC4626
{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /**
     * INITIALIZATION
     *
     */

    function initialize(
        address _governance,
        ERC20 _vaultAsset,
        address _wormholeRouter,
        L2BridgeEscrow _bridgeEscrow,
        EmergencyWithdrawalQueue _emergencyWithdrawalQueue,
        address forwarder,
        uint8[2] memory layerRatios,
        uint256[2] memory fees,
        uint256[2] memory ewqParams
    ) public initializer {
        __ERC20_init("USD Earn", "usdEarn");
        __UUPSUpgradeable_init();
        __Pausable_init();
        baseInitialize(_governance, _vaultAsset, _wormholeRouter, _bridgeEscrow);

        emergencyWithdrawalQueue = _emergencyWithdrawalQueue;
        l1Ratio = layerRatios[0];
        l2Ratio = layerRatios[1];
        rebalanceDelta = 10_000 * _asset.decimals();
        canTransferToL1 = true;
        canRequestFromL1 = true;
        lastTVLUpdate = uint128(block.timestamp);

        _grantRole(GUARDIAN_ROLE, _governance);
        _setTrustedForwarder(forwarder);

        withdrawalFee = fees[0];
        managementFee = fees[1];

        ewqMinAssets = ewqParams[0];
        ewqMinFee = ewqParams[1];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /**
     * META-TRANSACTION SUPPORT
     *
     */
    function _msgSender() internal view override (ContextUpgradeable, BaseRelayRecipient) returns (address) {
        return BaseRelayRecipient._msgSender();
    }

    function _msgData() internal view override (ContextUpgradeable, BaseRelayRecipient) returns (bytes calldata) {
        return BaseRelayRecipient._msgData();
    }

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }

    /**
     * @notice Set the trusted forwarder address
     * @param forwarder The new forwarder address
     */
    function setTrustedForwarder(address forwarder) external onlyGovernance {
        _setTrustedForwarder(forwarder);
    }

    /**
     * ERC4626 / ERC20 BASICS
     *
     */

    /// @notice See {IERC4626-asset}
    function asset() public view override (BaseVault, IERC4626) returns (address assetTokenAddress) {
        return address(_asset);
    }

    function decimals() public view override returns (uint8) {
        // E.g. for USDC, we want the initial price of a share to be $100.
        // For an initial price of 1 USDC / share we would have 1e6 * 1e8 / 1 = 1e14 shares given that we have 14 (6 + 8) decimals
        // in our share token. But since we want 100 USDC / share for the initial price, we add an extra two decimal places
        return _asset.decimals() + 10;
    }

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");

    /// @notice Pause the contract
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    /**
     * FEES
     *
     */

    /// @notice Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    /// @notice  Fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;
    /// @notice Minimal fee charged if withdrawal or redeem request is added to ewq, number is in assets amount.
    uint256 public ewqMinFee;
    /// @notice Minimal amount needed to enqueue a request to ewq, number is in assets amount.
    uint256 public ewqMinAssets;

    event ManagementFeeSet(uint256 oldFee, uint256 newFee);
    event WithdrawalFeeSet(uint256 oldFee, uint256 newFee);

    function setManagementFee(uint256 feeBps) external onlyGovernance {
        emit ManagementFeeSet({oldFee: managementFee, newFee: feeBps});
        managementFee = feeBps;
    }

    function setWithdrawalFee(uint256 feeBps) external onlyGovernance {
        emit WithdrawalFeeSet({oldFee: withdrawalFee, newFee: feeBps});
        withdrawalFee = feeBps;
    }

    function setEwqParams(uint256 _ewqMinFee, uint256 _ewqMinAssets) external onlyGovernance {
        ewqMinFee = _ewqMinFee;
        ewqMinAssets = _ewqMinAssets;
    }

    function _assessFees() internal override {
        // duration / SECS_PER_YEAR * feebps / MAX_BPS * totalSupply
        uint256 duration = block.timestamp - lastHarvest;

        uint256 feesBps = (duration * managementFee) / SECS_PER_YEAR;
        uint256 numSharesToMint = (feesBps * totalSupply()) / MAX_BPS;

        if (numSharesToMint == 0) {
            return;
        }
        _mint(governance, numSharesToMint);
    }

    uint256 constant SECS_PER_YEAR = 365 days;

    /**
     * DEPOSIT
     *
     */
    /// @notice See {IERC4626-deposit}
    function deposit(uint256 assets, address receiver) external whenNotPaused returns (uint256 shares) {
        shares = previewDeposit(assets);
        _deposit(assets, shares, receiver);
    }

    /// @notice See {IERC4626-mint}
    function mint(uint256 shares, address receiver) external whenNotPaused returns (uint256 assets) {
        assets = previewMint(shares);
        _deposit(assets, shares, receiver);
    }

    function _deposit(uint256 assets, uint256 shares, address receiver) internal {
        require(shares > 0, "L2Vault: zero shares");
        address caller = _msgSender();

        _asset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Deposit into strategies separately from `deposit` or `mint` to make these function less complex.
     * Having complicated execution path in `deposit` or `mint` flow leads to `out of gas` error for end users
     * due to inaccurate gas estimations.
     */
    function depositIntoStrategies(uint256 amount) external whenNotPaused onlyRole(HARVESTER) {
        // Deposit entire balance of `_asset` into strategies
        _depositIntoStrategies(amount);
    }

    /**
     * WITHDRAW / REDEEM
     *
     */
    EmergencyWithdrawalQueue public emergencyWithdrawalQueue;

    event EwqSet(EmergencyWithdrawalQueue indexed oldQ, EmergencyWithdrawalQueue indexed newQ);

    /**
     * @notice Update the address of the emergency withdrawal queue.
     * @param _ewq The new queue.
     */
    function setEwq(EmergencyWithdrawalQueue _ewq) external onlyGovernance {
        emit EwqSet({oldQ: emergencyWithdrawalQueue, newQ: _ewq});
        emergencyWithdrawalQueue = _ewq;
    }

    /// @notice See {IERC4626-redeem}
    function redeem(uint256 shares, address receiver, address owner) external whenNotPaused returns (uint256 assets) {
        assets = _redeem(_convertToAssets(shares, Rounding.Down), shares, receiver, owner);
    }

    /// @notice See {IERC4626-withdraw}
    function withdraw(uint256 assets, address receiver, address owner)
        external
        whenNotPaused
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets);
        _redeem(assets, shares, receiver, owner);
    }

    function _redeem(uint256 assets, uint256 shares, address receiver, address owner)
        internal
        returns (uint256 assetsToUser)
    {
        EmergencyWithdrawalQueue ewq = emergencyWithdrawalQueue;
        // Only real share amounts are allowed since we might create an ewq request
        require(shares <= balanceOf(owner) + ewq.ownerToDebt(owner), "L2Vault: min shares");

        uint256 assetsFee = _getWithdrawalFee(assets);
        assetsToUser = assets - assetsFee;

        // We must be able to repay all queued users and the current user
        uint256 assetDemand = assets + ewq.totalDebt();
        _liquidate(assetDemand);

        // The ewq does not need approval to burn shares
        address caller = _msgSender();
        if (caller != owner && caller != address(ewq)) _spendAllowance(owner, caller, shares);

        // Add to emergency withdrawal queue if there is not enough liquidity.
        if (_asset.balanceOf(address(this)) < assetDemand) {
            if (caller != address(ewq)) {
                // We need to enqueue, make sure that the requested amount is large enough.
                if (assets < ewqMinAssets) {
                    revert("L2Vault: bad enqueue, min assets");
                }
                ewq.enqueue(owner, receiver, shares);
                return 0;
            } else {
                revert("L2Vault: bad dequeue");
            }
        }

        // Burn shares and give user equivalent value in `_asset` (minus withdrawal fees)
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);

        _asset.safeTransfer(receiver, assetsToUser);
        _asset.safeTransfer(governance, assetsFee);
    }

    /**
     * EXCHANGE RATES
     *
     */
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /// @notice See {IERC4626-totalAssets}
    function totalAssets() public view returns (uint256 totalManagedAssets) {
        return vaultTVL() + l1TotalLockedValue - lockedProfit() - lockedTVL();
    }

    /// @notice See {IERC4626-convertToShares}
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = _convertToShares(assets, Rounding.Down);
    }

    /// @dev In previewDeposit we want to round down, but in previewWithdraw we want to round up
    function _convertToShares(uint256 assets, Rounding roundingDirection) internal view returns (uint256 shares) {
        // Even if there are no shares or assets in the vault, we start with 1 wei of asset and 1e8 shares
        // This helps mitigate price inflation attacks: https://github.com/transmissions11/solmate/issues/178
        // See https://www.rileyholterhus.com/writing/bunni as well.
        // The solution is inspired by YieldBox
        uint256 totalShares = totalSupply() + 1e8;
        uint256 _totalAssets = totalAssets() + 1;

        if (roundingDirection == Rounding.Up) {
            shares = assets.mulDivUp(totalShares, _totalAssets);
        } else {
            shares = assets.mulDivDown(totalShares, _totalAssets);
        }
    }

    /// @notice See {IERC4626-convertToAssets}
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = _convertToAssets(shares, Rounding.Down);
    }

    /// @dev In previewMint, we want to round up, but in previewRedeem we want to round down
    function _convertToAssets(uint256 shares, Rounding roundingDirection) internal view returns (uint256 assets) {
        uint256 totalShares = totalSupply() + 1e8;
        uint256 _totalAssets = totalAssets() + 1;

        if (roundingDirection == Rounding.Up) {
            assets = shares.mulDivUp(_totalAssets, totalShares);
        } else {
            assets = shares.mulDivDown(_totalAssets, totalShares);
        }
    }

    /// @notice See {IERC4626-previewDeposit}
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        return _convertToShares(assets, Rounding.Down);
    }

    /// @notice See {IERC4626-previewMint}
    function previewMint(uint256 shares) public view returns (uint256 assets) {
        assets = _convertToAssets(shares, Rounding.Up);
    }

    /// @notice See {IERC4626-previewWithdraw}
    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        shares = _convertToShares(assets, Rounding.Up);
    }

    /// @notice See {IERC4626-previewRedeem}
    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        uint256 rawAssets = _convertToAssets(shares, Rounding.Down);
        uint256 assetsFee = _getWithdrawalFee(rawAssets);
        assets = rawAssets - assetsFee;
    }

    /// @dev  Return amount of `asset` to be given to user after applying withdrawal fee
    function _getWithdrawalFee(uint256 tokenAmount) internal view returns (uint256) {
        uint256 feeAmount = tokenAmount.mulDivUp(withdrawalFee, MAX_BPS);
        if (_msgSender() == address(emergencyWithdrawalQueue)) {
            feeAmount = Math.max(feeAmount, ewqMinFee);
        }
        return feeAmount;
    }

    /**
     * DEPOSIT/WITHDRAWAL LIMITS
     */
    /// @notice See {IERC4626-maxDeposit}
    function maxDeposit(address receiver) public pure returns (uint256 maxAssets) {
        receiver;
        maxAssets = type(uint256).max;
    }

    /// @notice See {IERC4626-maxMint}
    function maxMint(address receiver) public pure returns (uint256 maxShares) {
        receiver;
        maxShares = type(uint256).max;
    }

    /// @notice See {IERC4626-maxRedeem}
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        maxShares = balanceOf(owner);
    }

    /// @notice See {IERC4626-maxWithdraw}
    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        maxAssets = _convertToAssets(balanceOf(owner), Rounding.Down);
    }

    /**
     * CROSS-CHAIN REBALANCING
     *
     */
    /// @notice TVL of L1 denominated in `asset` (e.g. USDC). This value will be updated by wormhole messages.
    uint256 public l1TotalLockedValue;

    // Represents the amount of tvl (in `token`) that should exist on L1 and L2
    // E.g. if layer1 == 1 and layer2 == 2 then 1/3 of the TVL should be on L1
    uint8 public l1Ratio;
    uint8 public l2Ratio;

    // Whether we can send or receive money from L1
    bool public canTransferToL1;
    bool public canRequestFromL1;

    /**
     * @notice The delta required to trigger a rebalance. The delta is the difference between current and ideal tvl
     * on a given layer
     * @dev Fits into the same slot as the four above variables.
     */
    uint224 public rebalanceDelta;

    /**
     * @notice Set the layer ratios
     * @param _l1Ratio The layer 1 ratio
     * @param _l2Ratio The layer 2 ratio
     */
    function setLayerRatios(uint8 _l1Ratio, uint8 _l2Ratio) external onlyGovernance {
        l1Ratio = _l1Ratio;
        l2Ratio = _l2Ratio;
        emit LayerRatiosSet({l1Ratio: l1Ratio, l2Ratio: l2Ratio});
    }

    event LayerRatiosSet(uint8 l1Ratio, uint8 l2Ratio);

    /**
     * @notice Set the rebalance delta
     * @param _rebalanceDelta The new rebalance delta
     */
    function setRebalanceDelta(uint224 _rebalanceDelta) external onlyGovernance {
        emit RebalanceDeltaSet({oldDelta: rebalanceDelta, newDelta: _rebalanceDelta});
        rebalanceDelta = _rebalanceDelta;
    }

    event RebalanceDeltaSet(uint224 oldDelta, uint224 newDelta);

    /// @notice The last time the tvl was updated. We need this to let L1 tvl updates unlock over time
    uint128 lastTVLUpdate;

    /// @notice See maxLockedProfit
    uint128 maxLockedTVL;

    /// @notice See lockedProfit. This is the same, except we are profiting from L1 tvl info
    function lockedTVL() public view returns (uint256) {
        uint256 _maxLockedTVL = maxLockedTVL;
        uint256 _lastTVLUpdate = lastTVLUpdate;
        if (block.timestamp >= _lastTVLUpdate + LOCK_INTERVAL) {
            return 0;
        }

        uint256 unlockedTVL = (_maxLockedTVL * (block.timestamp - _lastTVLUpdate)) / LOCK_INTERVAL;
        return _maxLockedTVL - unlockedTVL;
    }

    function receiveTVL(uint256 tvl, bool received) external {
        require(msg.sender == wormholeRouter, "L2Vault: only router");

        // If L1 has received the last transfer we sent it, unlock the L2->L1 bridge
        if (received && !canTransferToL1) {
            canTransferToL1 = true;
        }

        // Only rebalance if all cross chain transfers have been settled.
        // If the L1 vault is sending money (!canRequestFromL1), then its TVL could be wrong. Also
        // we don't to accidentally request money again. If (!canTransferToL1), we don't want to accidentally
        // send money when one transfer to L1 is already in progress
        if (!canTransferToL1 || !canRequestFromL1) {
            revert("Rebalance in progress");
        }

        // Update l1TotalLockedValue to match what we received from L1
        // Any increase in L1's tvl will unlock linearly, just as when harvesting from strategies
        uint256 oldL1TVL = l1TotalLockedValue;
        uint256 totalProfit = tvl > oldL1TVL ? tvl - oldL1TVL : 0;
        maxLockedTVL = uint128(totalProfit + lockedTVL());
        lastTVLUpdate = uint128(block.timestamp);
        l1TotalLockedValue = tvl;

        (bool invest, uint256 delta) = _computeRebalance();
        if (delta < rebalanceDelta) {
            return;
        }
        _l1L2Rebalance(invest, delta);
    }

    function _computeRebalance() internal view returns (bool, uint256) {
        uint256 numSlices = l1Ratio + l2Ratio;
        // We want to keep enough funds to satisfy emergency withdrawal queue plus l2Ratio of remaining funds
        // so that we have a l1Ratio:l2Ratio distribution in both layers after emergency withdrawal queue is
        // satisfied.
        uint256 l1IdealAmount =
            (l1Ratio * (vaultTVL() + l1TotalLockedValue - emergencyWithdrawalQueue.totalDebt())) / numSlices;

        bool invest;
        uint256 delta;
        if (l1IdealAmount >= l1TotalLockedValue) {
            invest = true;
            delta = l1IdealAmount - l1TotalLockedValue;
        } else {
            delta = l1TotalLockedValue - l1IdealAmount;
        }
        return (invest, delta);
    }

    function _l1L2Rebalance(bool invest, uint256 amount) internal {
        if (invest) {
            // Increase balance of `token` to `delta` by withdrawing from strategies.
            // Then transfer `amount` of `token` to L1.
            _liquidate(amount);
            uint256 amountToSend = Math.min(_asset.balanceOf(address(this)), amount);
            _transferToL1(amountToSend);
        } else {
            // Send message to L1 telling us how much should be transferred to this vault
            _divestFromL1(amount);
        }
    }

    function _transferToL1(uint256 amount) internal {
        // Send token
        _asset.safeTransfer(address(bridgeEscrow), amount);
        L2BridgeEscrow(address(bridgeEscrow)).withdraw(amount);
        emit TransferToL1(amount);

        // Update bridge state and L1 TVL
        // It's important to update this number now so that totalAssets() returns a smaller number
        canTransferToL1 = false;
        l1TotalLockedValue += amount;

        // Let L1 know how much money we sent
        L2WormholeRouter(wormholeRouter).reportFundTransfer(amount);
    }

    event TransferToL1(uint256 amount);

    function _divestFromL1(uint256 amount) internal {
        L2WormholeRouter(wormholeRouter).requestFunds(amount);
        canRequestFromL1 = false;
        emit RequestFromL1(amount);
    }

    event RequestFromL1(uint256 amount);

    function afterReceive(uint256 amount) external {
        require(_msgSender() == address(bridgeEscrow), "L2Vault: only escrow");
        l1TotalLockedValue -= amount;
        canRequestFromL1 = true;
    }

    /**
     * DETAILED PRICE INFO
     *
     */
    function detailedTVL() external view override returns (Number memory tvl) {
        tvl = Number({num: totalAssets(), decimals: _asset.decimals()});
    }

    function detailedPrice() external view override returns (Number memory price) {
        price = Number({num: convertToAssets(10 ** decimals()), decimals: _asset.decimals()});
    }

    function detailedTotalSupply() external view override returns (Number memory supply) {
        supply = Number({num: totalSupply(), decimals: decimals()});
    }
}
