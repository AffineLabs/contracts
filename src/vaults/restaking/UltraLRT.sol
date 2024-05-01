// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// upgrading contracts
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// storage contract
import {UltraLRTStorage} from "src/vaults/restaking/UltraLRTStorage.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {AffineDelegator} from "src/vaults/restaking/AffineDelegator.sol";
import {DelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";

contract UltraLRT is
    ERC4626Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    AffineGovernable,
    UltraLRTStorage
{
    using SafeTransferLib for ERC20;

    function initialize(
        address _governance,
        address vaultAsset,
        address _delegatorImpl,
        string memory _name,
        string memory _symbol
    ) external initializer {
        governance = _governance;

        // init token
        __ERC4626_init(IERC20MetadataUpgradeable(vaultAsset));
        __ERC20_init(_name, _symbol);

        // init control
        __AccessControl_init();
        __Pausable_init();
        // All roles use the default admin role
        // Governance has the admin role and all roles
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GUARDIAN_ROLE, governance);
        _grantRole(HARVESTER, governance);

        //
        beacon = new DelegatorBeacon(_delegatorImpl, governance);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /// @notice Pause the contract
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /*//////////////////////////////////////////////////////////////
                            DECIMALS
    //////////////////////////////////////////////////////////////*/

    /// @dev E.g. if the asset has 18 decimals, and initialSharesPerAsset is 1e8, then the vault has 26 decimals. And
    /// "one" `asset` will be worth "one" share (where "one" means 10 ** token.decimals()).
    function decimals() public view virtual override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return ERC20(asset()).decimals() + _initialShareDecimals();
    }

    /// @notice The amount of shares to mint per wei of `asset` at genesis.
    function initialSharesPerAsset() public pure virtual returns (uint256) {
        return 10 ** _initialShareDecimals();
    }

    /// @notice Each wei of `asset` at genesis is worth 10 ** (initialShareDecimals) shares.
    function _initialShareDecimals() internal pure virtual returns (uint8) {
        return 8;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT ETH
    //////////////////////////////////////////////////////////////*/

    event Referral(address indexed depositor, uint256 referralId);

    function depositETH(address receiver, uint256 _referrerId)
        external
        payable
        whenNotPaused
        whenDepositNotPaused
        returns (uint256)
    {
        //TODO if (msg.value == 0) revert ReStakingErrors.DepositAmountCannotBeZero();
        //TODO if (_for == address(0)) revert ReStakingErrors.CannotDepositForZeroAddress();
        //TODO if (!hasRole(APPROVED_TOKEN, address(WETH))) revert ReStakingErrors.TokenNotAllowedForStaking();

        uint256 assets = STETH.submit{value: msg.value}(address(this)); //TODO check for referral
        // emit Deposit(++eventId, _for, address(WETH), msg.value);

        uint256 shares = previewDeposit(assets);

        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, assets, shares);
        emit Referral(receiver, _referrerId);
        return shares;
    }

    function deposit(uint256 assets, address receiver, uint256 _referrerId) public returns (uint256 shares) {
        shares = deposit(assets, receiver);
        emit Referral(receiver, _referrerId);
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        whenDepositNotPaused
        returns (uint256)
    {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver, uint256 _referrerId) public returns (uint256 assets) {
        assets = mint(shares, receiver);
        emit Referral(receiver, _referrerId);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        whenDepositNotPaused
        returns (uint256)
    {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IERC4262-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev See {IERC4262-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transfered, which is a valid state.

        // TODO: calculate fees

        if (!canWithdraw(assets)) {
            // do withdrawal request
            _transfer(_msgSender(), address(escrow), shares);
            escrow.registerWithdrawalRequest(receiver, shares);
            // do immediate withdrawal request for user
            _liquidationRequest(assets);
            return;
        }
        _burn(owner, shares);

        uint256 assetsToReceive = Math.min(ERC20(asset()).balanceOf(address(this)), assets);

        require(assetsToReceive + ST_ETH_TRANSFER_BUFFER >= assets, "Invalid withdrawal");
        ERC20(asset()).safeTransfer(receiver, assetsToReceive);

        emit Withdraw(caller, receiver, owner, assetsToReceive, shares);
    }

    function canWithdraw(uint256 assets) public view returns (bool) {
        if (_msgSender() == address(escrow)) {
            return true;
        }
        uint256 escrowDebt = address(escrow) == address(0) ? 0 : escrow.totalDebt();
        return escrowDebt == 0 && (ERC20(asset()).balanceOf(address(this)) + ST_ETH_TRANSFER_BUFFER) >= assets;
    }

    /*//////////////////////////////////////////////////////////////
                            ESCROW 
    //////////////////////////////////////////////////////////////*/

    function setWithdrawalEscrow(WithdrawalEscrowV2 _escrow) external onlyGovernance {
        require(address(escrow) == address(0) || escrow.totalDebt() == 0, "ULRT: Clear escrow debt.");
        require(address(_escrow.vault()) == address(this), "ULRT: Invalid escrow vault.");

        escrow = _escrow;
    }

    function endEpoch() external onlyRole(HARVESTER) {
        escrow.endEpoch();
    }

    function liquidationRequest(uint256 assets) external onlyRole(HARVESTER) {
        _liquidationRequest(assets);
    }

    function _liquidationRequest(uint256 assets) internal {
        for (uint256 i = 0; i < delegatorCount; i++) {
            IDelegator delegator = delegatorQueue[i];
            uint256 assetsToRequest = Math.min(delegator.withdrawableAssets(), assets);
            _delegatorWithdrawRequest(delegator, assetsToRequest);
            if (assetsToRequest == assets) {
                break;
            }
            assets -= assetsToRequest;
        }
    }

    function delegatorWithdrawRequest(IDelegator delegator, uint256 assets) external onlyRole(HARVESTER) {
        _delegatorWithdrawRequest(delegator, assets);
    }

    function _delegatorWithdrawRequest(IDelegator delegator, uint256 assets) internal {
        require(assets <= delegator.withdrawableAssets(), "Invalid assets");
        delegator.requestWithdrawal(assets);
    }

    function resolveDebt() external onlyRole(HARVESTER) {
        if (escrow.resolvingEpoch() < escrow.currentEpoch()) {
            uint256 debtShare = escrow.getDebtToResolve();
            uint256 assets = previewRedeem(debtShare);
            if ((ERC20(asset()).balanceOf(address(this)) + ST_ETH_TRANSFER_BUFFER) >= assets) {
                escrow.resolveDebtShares();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            DELEGATOR 
    //////////////////////////////////////////////////////////////*/
    // todo check a valid operator address
    function createDelegator(address _operator) external onlyGovernance {
        require(delegatorCount < MAX_DELEGATOR, "Max Delegator");
        BeaconProxy bProxy = new BeaconProxy(
            address(beacon), abi.encodeWithSelector(AffineDelegator.initialize.selector, address(this), _operator)
        );
        delegatorQueue[delegatorCount] = IDelegator(address(bProxy));

        DelegatorInfo memory info;
        info.balance = 0;
        info.isActive = true;
        delegatorMap[address(bProxy)] = info;

        delegatorCount = delegatorCount + 1;
    }

    function dropDelegator(address _delegator) external onlyGovernance {
        require(IDelegator(_delegator).totalLockedValue() == 0, "delegator non-zero tvl");

        DelegatorInfo memory info = delegatorMap[_delegator];

        require(info.isActive, "Inactive delegator");
        require(info.balance == 0, "Require harvest");
        info.isActive = false;
        for (uint8 i = 0; i < delegatorCount; i++) {
            if (address(delegatorQueue[i]) == _delegator) {
                delegatorQueue[i] = delegatorQueue[delegatorCount - 1];
                delegatorQueue[delegatorCount - 1] = IDelegator(address(0));
                delegatorCount = delegatorCount - 1;

                delegatorMap[_delegator] = info;
                break;
            }
        }
    }

    function harvest() external onlyRole(HARVESTER) {
        require(block.timestamp > lastHarvest + LOCK_INTERVAL, "Profit unlocking");

        uint256 newDelegatorAssets;
        for (uint8 i = 0; i < delegatorCount; i++) {
            uint256 currentDelegatorTVL = delegatorQueue[i].totalLockedValue();
            // TODO map utilization
            delegatorMap[address(delegatorQueue[i])].balance = uint248(currentDelegatorTVL);
            newDelegatorAssets += currentDelegatorTVL;
        }

        // TODO: incremental distribution of assets
        if (delegatorAssets < newDelegatorAssets) {
            maxLockedProfit = newDelegatorAssets - delegatorAssets;
        } else {
            maxLockedProfit = 0;
        }
        lastHarvest = block.timestamp;
        delegatorAssets = newDelegatorAssets;
    }

    function collectDelegatorDebt() external onlyRole(HARVESTER) {
        uint256 currentDelegatorAssets = delegatorAssets;

        for (uint8 i = 0; i < delegatorCount; i++) {
            IDelegator delegator = delegatorQueue[i];
            uint256 prevTVL = delegatorMap[address(delegator)].balance;
            delegator.withdraw();
            uint256 newTVL = delegator.totalLockedValue();
            delegatorMap[address(delegator)].balance = uint248(newTVL);
            currentDelegatorAssets -= (prevTVL > newTVL ? prevTVL - newTVL : 0);
        }

        delegatorAssets = currentDelegatorAssets;
    }

    function delegateToDelegator(address _delegator, uint256 amount) external onlyRole(HARVESTER) {
        IDelegator delegator = IDelegator(_delegator);
        uint256 availableAssets = ERC20(asset()).balanceOf(address(this));

        require(delegatorMap[_delegator].isActive, "Inactive delegator");
        require(availableAssets <= amount, "invalid assets");

        // delegate
        ERC20(asset()).approve(_delegator, amount);
        delegator.delegate(amount);

        delegatorMap[_delegator].balance += uint248(amount);
        delegatorAssets += uint248(amount);
    }

    /**
     * @notice Current locked profit amount.
     * @dev Profit unlocks uniformly over `LOCK_INTERVAL` seconds after the last harvest
     */
    function lockedProfit() public view virtual returns (uint256) {
        if (block.timestamp >= lastHarvest + LOCK_INTERVAL) {
            return 0;
        }

        uint256 unlockedProfit = (maxLockedProfit * (block.timestamp - lastHarvest)) / LOCK_INTERVAL;
        return maxLockedProfit - unlockedProfit;
    }

    /*//////////////////////////////////////////////////////////////
                            TVL
    //////////////////////////////////////////////////////////////*/

    // TODO -- calculate tvl
    // get assets
    // get shares

    function totalAssets() public view override returns (uint256) {
        return ERC20(asset()).balanceOf(address(this)) + delegatorAssets - lockedProfit();
    }

    /*//////////////////////////////////////////////////////////////
                                  FEES
    //////////////////////////////////////////////////////////////*/

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
}
