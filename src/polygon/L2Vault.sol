// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseRelayRecipient } from "@opengsn/contracts/src/BaseRelayRecipient.sol";

import { BaseVault } from "../BaseVault.sol";
import { IWormhole } from "../interfaces/IWormhole.sol";
import { BridgeEscrow } from "../BridgeEscrow.sol";
import { ICreate2Deployer } from "../interfaces/ICreate2Deployer.sol";
import { DetailedShare } from "./Detailed.sol";
import { L2WormholeRouter } from "./L2WormholeRouter.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";

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

    // Wormhole Router
    L2WormholeRouter public wormholeRouter;

    // TVL of L1 denominated in `token` (e.g. USDC). This value will be updated by oracle.
    uint256 public L1TotalLockedValue;

    /////// Cross chain rebalancing

    // Represents the amount of tvl (in `token`) that should exist on L1 and L2
    // E.g. if layer1 == 1 and layer2 == 2 then 1/3 of the TVL should be on L1
    struct LayerBalanceRatios {
        uint256 layer1;
        uint256 layer2;
    }
    LayerBalanceRatios public layerRatios;

    // Whether we can send or receive money from L1
    bool public canTransferToL1;
    bool public canRequestFromL1;

    event SendToL1(uint256 amount);
    event ReceiveFromL1(uint256 amount);

    /** Fees
     **************************************************************************/

    // Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    // fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;

    function setManagementFee(uint256 feeBps) external onlyGovernance {
        managementFee = feeBps;
    }

    function setWithdrawalFee(uint256 feeBps) external onlyGovernance {
        withdrawalFee = feeBps;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function initialize(
        address _governance,
        ERC20 _token,
        IWormhole _wormhole,
        L2WormholeRouter _wormholeRouter,
        BridgeEscrow _BridgeEscrow,
        address forwarder,
        uint256 L1Ratio,
        uint256 L2Ratio,
        uint256[2] memory fees
    ) public initializer {
        __ERC20_init("Alpine Save", "alpSave");
        __UUPSUpgradeable_init();
        __Pausable_init();
        BaseVault.init(_governance, _token, _wormhole, _BridgeEscrow);
        wormholeRouter = _wormholeRouter;
        layerRatios = LayerBalanceRatios({ layer1: L1Ratio, layer2: L2Ratio });
        canTransferToL1 = true;
        canRequestFromL1 = true;

        _setTrustedForwarder(forwarder);

        withdrawalFee = fees[0];
        managementFee = fees[1];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    function _msgSender() internal view override(Context, ContextUpgradeable, BaseRelayRecipient) returns (address) {
        return BaseRelayRecipient._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ContextUpgradeable, BaseRelayRecipient)
        returns (bytes calldata)
    {
        return BaseRelayRecipient._msgData();
    }

    function versionRecipient() external pure override returns (string memory) {
        return "1";
    }

    function togglePause() external onlyRole(harvesterRole) {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function decimals() public view override returns (uint8) {
        return _asset.decimals();
    }

    /** ERC4626
     **************************************************************************/
    function asset() public view override(BaseVault, IERC4626) returns (address assetTokenAddress) {
        return address(_asset);
    }

    function totalAssets() public view returns (uint256 totalManagedAssets) {
        return vaultTVL() - lockedProfit() + L1TotalLockedValue;
    }

    function maxDeposit(address receiver) public view returns (uint256 maxAssets) {
        receiver;
        maxAssets = type(uint256).max;
    }

    function maxMint(address receiver) public view returns (uint256 maxShares) {
        receiver;
        maxShares = type(uint256).max;
    }

    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        maxShares = balanceOf(owner);
    }

    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        maxAssets = convertToAssets(balanceOf(owner));
    }

    /** DEPOSIT
     **************************************************************************/
    function deposit(uint256 assets, address receiver) external whenNotPaused returns (uint256 shares) {
        shares = convertToShares(assets);
        address caller = _msgSender();

        _asset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);

        // deposit entire balance of `_asset` into strategies
        depositIntoStrategies();
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) {
            shares = assets;
        } else {
            shares = (assets * totalShares) / totalAssets();
        }
    }

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        return convertToShares(assets);
    }

    function mint(uint256 shares, address receiver) external whenNotPaused returns (uint256 assets) {
        assets = previewMint(shares);
        address caller = _msgSender();

        _asset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);

        depositIntoStrategies();
    }

    function previewMint(uint256 shares) public view returns (uint256 assets) {
        // TODO: round up
        assets = convertToAssets(shares);
    }

    /** WITHDRAW / REDEEM
     **************************************************************************/

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external whenNotPaused returns (uint256 assets) {
        assets = previewRedeem(shares);

        // TODO: handle case where the user is trying to withdraw more value than actually exists in the vault
        if (assets > _asset.balanceOf(address(this))) {}

        address caller = _msgSender();
        _spendAllowance(owner, caller, shares);

        // Burn shares and give user equivalent value in `_asset` (minus withdrawal fees)
        _burn(owner, shares);

        emit Withdraw(caller, receiver, owner, assets, shares);
        _asset.safeTransfer(receiver, assets);
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        uint256 rawAssets = convertToAssets(shares);
        uint256 assetsFee = _getWithdrawalFee(rawAssets);
        return rawAssets - assetsFee;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external whenNotPaused returns (uint256 shares) {
        // If the owner does not have enough shares, we revert
        uint256 assetsFee = _getWithdrawalFee(assets);
        shares = previewWithdraw(assets + assetsFee);

        address caller = _msgSender();
        _spendAllowance(owner, caller, shares);
        _burn(owner, shares);

        emit Withdraw(caller, receiver, owner, assets, shares);
        _asset.safeTransfer(receiver, assets);
        _asset.safeTransfer(governance, assetsFee);
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) {
            assets = 0;
        } else {
            assets = shares * (totalAssets() / totalShares);
        }
    }

    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        // TODO: make sure to round up when doing this conversion
        // Deduct withdrawal fee from `assets`
        shares = convertToShares(assets);
    }

    // Return number of tokens to be given to user after applying withdrawal fee
    function _getWithdrawalFee(uint256 tokenAmount) internal view returns (uint256) {
        // TODO: round up here
        uint256 feeAmount = (tokenAmount * withdrawalFee) / MAX_BPS;
        return feeAmount;
    }

    function _assessFees() internal override {
        // duration / SECS_PER_YEAR * feebps / MAX_BPS * totalSupply
        uint256 duration = block.timestamp - lastHarvest;

        uint256 feesBps = (duration * managementFee) / SECS_PER_YEAR;
        uint256 numSharesToMint = (feesBps * totalSupply()) / MAX_BPS;

        if (numSharesToMint == 0) return;
        _mint(governance, numSharesToMint);
    }

    function receiveTVL(uint256 tvl, bool received) external {
        require(msg.sender == address(wormholeRouter), "Only wormhole router");

        // If L1 has received the last transfer we sent it, unlock the L2->L1 bridge
        if (received && !canTransferToL1) canTransferToL1 = true;

        // If L1 is sending us money (!canRequestFromL1), the TVL its sending could be wrong
        if (canRequestFromL1) L1TotalLockedValue = tvl;

        // Only rebalance if all cross chain transfers have been settled.
        // If the L1 vault is sending money (!canRequestFromL1), then its TVL could be wrong. Also
        // we don't to accidentally request money again. If (!canTransferToL1), we don't want to accidentally
        // send money when one transfer to L1 is already in progress
        if (!canTransferToL1 || !canRequestFromL1) return;

        (bool invest, uint256 delta) = _computeRebalance();
        // if (delta < 100_000 * 10 ** decimals()) return;
        // TODO: use the condition above eventually, this is just for testing
        if (delta == 0) return;

        _L1L2Rebalance(invest, delta);
    }

    function _computeRebalance() internal view returns (bool, uint256) {
        uint256 numSlices = layerRatios.layer1 + layerRatios.layer2;
        uint256 L1IdealAmount = (layerRatios.layer1 * totalAssets()) / numSlices;

        bool invest;
        uint256 delta;
        if (L1IdealAmount >= L1TotalLockedValue) {
            invest = true;
            delta = L1IdealAmount - L1TotalLockedValue;
        } else {
            delta = L1TotalLockedValue - L1IdealAmount;
        }
        return (invest, delta);
    }

    function _L1L2Rebalance(bool invest, uint256 amount) internal {
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

    // TODO: liquidate properly
    function _transferToL1(uint256 amount) internal {
        // Send token
        _asset.safeTransfer(address(bridgeEscrow), amount);
        bridgeEscrow.l2Withdraw(amount);
        emit SendToL1(amount);

        // Update bridge state and L1 TVL
        // It's important to update this number now so that totalAssets() returns a smaller number
        canTransferToL1 = false;
        L1TotalLockedValue += amount;

        // Let L1 know how much money we sent
        wormholeRouter.reportTransferredFund(amount);
    }

    function _divestFromL1(uint256 amount) internal {
        // TODO: make wormhole address, consistencyLevel configurable
        wormholeRouter.requestFunds(amount);
        canRequestFromL1 = false;
    }

    function afterReceive(uint256 amount) external {
        require(_msgSender() == address(bridgeEscrow), "Only L2 BridgeEscrow.");
        L1TotalLockedValue -= amount;
        canRequestFromL1 = true;
        emit ReceiveFromL1(amount);
    }

    /** DETAILED PRICE INFO
     **************************************************************************/

    /// @dev The vault has as many decimals as the input token does
    function detailedTVL() external view override returns (Number memory tvl) {
        tvl = Number({ num: totalAssets(), decimals: decimals() });
    }

    function detailedPrice() external view override returns (Number memory price) {
        price = Number({ num: (totalAssets() * 10**decimals()) / totalSupply(), decimals: decimals() });
    }

    function detailedTotalSupply() external view override returns (Number memory supply) {
        supply = Number({ num: totalSupply(), decimals: decimals() });
    }
}
