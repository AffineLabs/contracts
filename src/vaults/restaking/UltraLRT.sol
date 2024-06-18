// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

// upgrading contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// storage contract
import {UltraLRTStorage} from "src/vaults/restaking/UltraLRTStorage.sol";
import {WithdrawalEscrowV2} from "src/vaults/restaking/WithdrawalEscrowV2.sol";

// governance contract
import {AffineGovernable} from "src/utils/audited/AffineGovernable.sol";

import {ReStakingErrors} from "src/libs/ReStakingErrors.sol";
import {IDelegator} from "src/vaults/restaking/IDelegator.sol";
import {IDelegatorFactory} from "src/vaults/restaking/DelegatorFactory.sol";
import {IDelegatorBeacon} from "src/vaults/restaking/DelegatorBeacon.sol";

/**
 * @title UltraLRT
 * @notice UltraLRT is a liquid staking vault that allows users to deposit staked assets and receive shares in return.
 * The shares can be redeemed for the underlying assets at any time. Vault will delegate the assets to the delegators and harvest the profit.
 * The vault will also distribute the profits to the holders.
 */
contract UltraLRT is
    ERC4626Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    AffineGovernable,
    ReentrancyGuard,
    UltraLRTStorage
{
    /**
     * @notice Initialize the UltraLRT contract
     * @param _governance The address of the governance contract
     * @param _asset The address of the asset token
     * @param _delegatorBeacon The address of the delegator beacon
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     */
    function initialize(
        address _governance,
        address _asset,
        address _delegatorBeacon,
        string memory _name,
        string memory _symbol
    ) external initializer {
        governance = _governance;

        // init token
        __ERC4626_init(IERC20MetadataUpgradeable(_asset));
        __ERC20_init(_name, _symbol);

        // init control
        __AccessControl_init();
        __Pausable_init();
        // All roles use the default admin role
        // Governance has the admin role and all roles
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _grantRole(GUARDIAN_ROLE, governance);
        _grantRole(HARVESTER, governance);

        // beacon proxy
        /// @dev check for the owner of the beacon: Invalid beacon
        require(IDelegatorBeacon(_delegatorBeacon).owner() == governance, "ULRT: IB");
        beacon = _delegatorBeacon;
    }
    /**
     * @notice Upgrade the UltraLRT contract
     * @param newImplementation The address of the new implementation contract
     */

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    /**
     * @notice The maximum amount of assets that can be deposited into the vault
     * @return The maximum amount of assets that can be deposited
     * @dev See {IERC4262-maxDeposit}.
     */
    function maxDeposit(address) public view virtual override returns (uint256) {
        bool isCollateralized = totalAssets() > 0 || totalSupply() == 0;
        return isCollateralized ? type(uint128).max : 0;
    }

    /**
     * @notice The maximum amount of shares that can be minted
     * @return The maximum amount of shares that can be minted
     * @dev See {IERC4262-maxMint}.
     */
    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint128).max;
    }

    /**
     * @notice set the delegator factory
     * @param _factory The address of the delegator factory
     * @dev factory must have the vault set to this vault
     */
    function setDelegatorFactory(address _factory) external onlyGovernance {
        if (IDelegatorFactory(_factory).vault() != address(this)) revert ReStakingErrors.InvalidDelegatorFactory();

        delegatorFactory = _factory;
    }

    /// @notice Pause the contract
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            DECIMALS
    //////////////////////////////////////////////////////////////*/

    /// @dev E.g. if the asset has 18 decimals, and initialSharesPerAsset is 1e8, then the vault has 26 decimals. And
    /// "one" `asset` will be worth "one" share (where "one" means 10 ** token.decimals()).
    function decimals() public view virtual override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
        return IERC20MetadataUpgradeable(asset()).decimals() + _initialShareDecimals();
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

    /**
     * @notice Pause the deposit
     */
    function pauseDeposit() external onlyGovernance {
        depositPaused = 1;
    }

    /**
     * @notice Unpause the deposit
     */
    function unpauseDeposit() external onlyGovernance {
        depositPaused = 0;
    }

    /**
     * @notice Deposit assets into the vault
     * @param receiver The address of the receiver
     * @return The amount of shares minted
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        whenDepositNotPaused
        nonReentrant
        returns (uint256)
    {
        if (assets > maxDeposit(receiver)) revert ReStakingErrors.ExceedsDepositLimit();

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /**
     * @notice mint specific amount of shares
     * @param shares The amount of shares to mint
     * @param receiver The address of the receiver
     * @return The amount of assets minted
     */
    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        whenDepositNotPaused
        nonReentrant
        returns (uint256)
    {
        if (shares > maxMint(receiver)) revert ReStakingErrors.ExceedsMintLimit();

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw assets from the vault
     * @param assets The amount of assets to withdraw
     * @param receiver The address of the receiver
     * @param owner The address of the owner
     * @return The amount of shares burned
     * @dev See {IERC4262-withdraw}.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (assets > maxWithdraw(owner)) revert ReStakingErrors.ExceedsWithdrawLimit();

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @notice Redeem shares from the vault
     * @param shares The amount of shares to redeem
     * @param receiver The address of the receiver
     * @param owner The address of the owner
     * @return The amount of assets redeemed
     * @dev See {IERC4262-redeem}.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (shares > maxRedeem(owner)) revert ReStakingErrors.ExceedsRedeemLimit();

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @notice withdraw from the vault
     * @param caller The address of the caller
     * @param receiver The address of the receiver
     * @param owner The address of the owner
     * @param assets The amount of assets to withdraw
     * @param shares The amount of shares to burn
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
            // _liquidationRequest(assets);
            emit Withdraw(caller, receiver, owner, assets, shares);
            return;
        }
        _burn(owner, shares);

        uint256 assetsToReceive = Math.min(vaultAssets(), assets);

        if (assetsToReceive + ST_ETH_TRANSFER_BUFFER < assets) revert ReStakingErrors.InsufficientLiquidAssets();

        IERC20MetadataUpgradeable(asset()).transfer(receiver, assetsToReceive);

        emit Withdraw(caller, receiver, owner, assetsToReceive, shares);
    }

    /**
     * @notice Check if the withdrawal can be done
     * @param assets The amount of assets to withdraw
     * @return True if the withdrawal can be done
     */
    function canWithdraw(uint256 assets) public view returns (bool) {
        if (_msgSender() == address(escrow)) {
            return true;
        }
        uint256 escrowDebt = address(escrow) == address(0) ? 0 : escrow.totalDebt();
        return escrowDebt == 0 && (vaultAssets() + ST_ETH_TRANSFER_BUFFER) >= assets;
    }

    /*//////////////////////////////////////////////////////////////
                            ESCROW 
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the withdrawal escrow
     * @param _escrow The address of the withdrawal escrow
     * @dev The escrow must have the vault set to this vault
     *     @dev existing escrow debt must be zero
     */
    function setWithdrawalEscrow(WithdrawalEscrowV2 _escrow) external onlyGovernance {
        if (address(escrow) != address(0) && escrow.totalDebt() > 0) revert ReStakingErrors.ExistingEscrowDebt();

        if (address(_escrow.vault()) != address(this)) revert ReStakingErrors.InvalidEscrowVault();

        escrow = _escrow;
    }

    /*//////////////////////////////////////////////////////////////
                            EPOCH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice End the current epoch
     * @dev Only the harvester can end the epoch anytime
     * @dev for other The epoch can only be ended if the last epoch was ended at least `LOCK_INTERVAL` seconds ago
     */
    function endEpoch() external {
        if (!hasRole(HARVESTER, msg.sender) && (block.timestamp - lastEpochTime) < LOCK_INTERVAL) {
            revert ReStakingErrors.RunningEpoch();
        }
        /// @dev only harvester can end and epoch after
        uint256 closingEpoch = escrow.currentEpoch();
        escrow.endEpoch();
        lastEpochTime = block.timestamp;

        /// @request for liquidation in case called by non-harvester
        (uint256 shares,) = escrow.epochInfo(closingEpoch);
        uint256 assets = convertToAssets(shares);
        _liquidationRequest(assets);
    }

    /**
     * @notice Do liquidation request to delegators
     * @param assets The amount of assets to liquidate
     * @dev Only the harvester can do the liquidation request
     */
    function liquidationRequest(uint256 assets) external onlyRole(HARVESTER) {
        _liquidationRequest(assets);
    }

    /**
     * @notice Do liquidation request to delegators
     * @param assets The amount of assets to liquidate
     */
    function _liquidationRequest(uint256 assets) internal {
        for (uint256 i = 0; i < delegatorCount && assets > 0; i++) {
            IDelegator delegator = delegatorQueue[i];
            if (delegator.withdrawableAssets() > 0) {
                uint256 assetsToRequest = Math.min(delegator.withdrawableAssets(), assets);
                delegator.requestWithdrawal(assetsToRequest);
                assets -= assetsToRequest;
            }
        }
    }

    /**
     * @notice Withdraw from speicific delegator
     * @param delegator The address of the delegator
     * @param assets The amount of assets to withdraw
     */
    function delegatorWithdrawRequest(IDelegator delegator, uint256 assets) external onlyRole(HARVESTER) {
        if (assets > delegator.withdrawableAssets()) revert ReStakingErrors.ExceedsDelegatorWithdrawableAssets();
        delegator.requestWithdrawal(assets);
    }

    /**
     * @notice Resolve the debt
     */
    function resolveDebt() external {
        if (escrow.resolvingEpoch() == escrow.currentEpoch()) {
            revert ReStakingErrors.NoResolvingEpoch();
        }
        uint256 assets = previewRedeem(escrow.getDebtToResolve());

        // try liquidating assets
        if ((vaultAssets() + ST_ETH_TRANSFER_BUFFER) < assets) {
            _getDelegatorLiquidAssets(assets);
        }

        if ((vaultAssets() + ST_ETH_TRANSFER_BUFFER) < assets) {
            revert ReStakingErrors.InsufficientLiquidAssets();
        }
        escrow.resolveDebtShares();
    }

    /*//////////////////////////////////////////////////////////////
                            DELEGATOR 
    //////////////////////////////////////////////////////////////*/
    // todo check a valid operator address

    /**
     * @notice Create a new delegator
     * @param _operator The address of the operator
     */
    function createDelegator(address _operator) external onlyGovernance {
        if (delegatorCount >= MAX_DELEGATOR) revert ReStakingErrors.ExceedsMaxDelegatorLimit();
        if (delegatorFactory == address(0)) revert ReStakingErrors.InvalidDelegatorFactory();

        address newDelegator = IDelegatorFactory(delegatorFactory).createDelegator(_operator);

        delegatorQueue[delegatorCount] = IDelegator(newDelegator);

        DelegatorInfo memory info;
        info.balance = 0;
        info.isActive = true;
        delegatorMap[newDelegator] = info;
        delegatorCount = delegatorCount + 1;
    }

    /**
     * @notice Drop a delegator
     * @param _delegator The address of the delegator
     */
    function dropDelegator(address _delegator) external onlyGovernance {
        if (IDelegator(_delegator).totalLockedValue() > 0) revert ReStakingErrors.NonZeroEmptyDelegatorTVL();

        DelegatorInfo memory info = delegatorMap[_delegator];

        if (!info.isActive) revert ReStakingErrors.InactiveDelegator();
        if (info.balance > 0) revert ReStakingErrors.RequireHarvest();

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

    /**
     * @notice Harvest the profit
     */
    function harvest() external onlyRole(HARVESTER) {
        if (block.timestamp <= lastHarvest + LOCK_INTERVAL) revert ReStakingErrors.ProfitUnlocking();

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

    /**
     * @notice Collect the delegator debt
     * @dev will withdraw the liquid assets from the delegators
     */
    function collectDelegatorDebt() external onlyRole(HARVESTER) {
        _getDelegatorLiquidAssets(totalAssets());
    }

    /**
     * @notice Get the delegator liquid assets
     * @param assets The amount of assets to get
     */
    function _getDelegatorLiquidAssets(uint256 assets) internal {
        uint256 currentDelegatorAssets = delegatorAssets;

        for (uint8 i = 0; i < delegatorCount && assets > 0; i++) {
            IDelegator delegator = delegatorQueue[i];
            // check for zero assets
            if (IERC20MetadataUpgradeable(asset()).balanceOf(address(delegator)) < 2) {
                /// @dev taking into account transfer 1 steth has issue.
                continue;
            }
            uint256 prevTVL = delegatorMap[address(delegator)].balance;
            delegator.withdraw();
            uint256 newTVL = delegator.totalLockedValue();
            delegatorMap[address(delegator)].balance = uint248(newTVL);
            currentDelegatorAssets -= (prevTVL > newTVL ? prevTVL - newTVL : 0);

            if ((vaultAssets() + ST_ETH_TRANSFER_BUFFER) < assets) {
                break;
            }
        }

        delegatorAssets = currentDelegatorAssets;
    }

    /**
     * @notice Delegate the assets to the delegator
     * @param _delegator The address of the delegator
     * @param amount The amount of assets to delegate
     */
    function delegateToDelegator(address _delegator, uint256 amount) external onlyRole(HARVESTER) {
        IDelegator delegator = IDelegator(_delegator);

        DelegatorInfo memory info = delegatorMap[_delegator];

        if (!info.isActive) revert ReStakingErrors.InactiveDelegator();
        if (vaultAssets() < amount) revert ReStakingErrors.InsufficientLiquidAssets();

        // delegate
        IERC20MetadataUpgradeable(asset()).approve(_delegator, amount);
        delegator.delegate(amount);

        info.balance += uint248(amount);
        delegatorMap[_delegator] = info;
        delegatorAssets += amount;
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

    /**
     * @notice Get the total assets
     */
    function totalAssets() public view override returns (uint256) {
        return vaultAssets() + delegatorAssets - lockedProfit();
    }

    /**
     * @notice Get the vault liquid assets
     */
    function vaultAssets() public view returns (uint256) {
        return IERC20MetadataUpgradeable(asset()).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                  FEES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the management fee
     */
    function setManagementFee(uint256 feeBps) external onlyGovernance {
        managementFee = feeBps;
    }

    /**
     * @notice Set the withdrawal fee
     */
    function setWithdrawalFee(uint256 feeBps) external onlyGovernance {
        withdrawalFee = feeBps;
    }

    /*//////////////////////////////////////////////////////////////
                                  Balancer Interface for pice
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice returns the per share assets
     */
    function getRate() external view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }
}
