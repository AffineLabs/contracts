// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.16;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {AffineVault} from "../AffineVault.sol";
import {Affine4626} from "../Affine4626.sol";
import {DetailedShare} from "../both/Detailed.sol";

contract Vault is AffineVault, Affine4626, DetailedShare {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    function initialize(address _governance, address vaultAsset) external initializer {
        AffineVault.baseInitialize(_governance, ERC20(vaultAsset));
        __ERC20_init("USD Earn", "usdEarn");
        ERC4626Upgradeable.__ERC4626_init(IERC20MetadataUpgradeable(vaultAsset));
    }

    function asset() public view override (AffineVault, ERC4626Upgradeable) returns (address) {
        return AffineVault.asset();
    }

    /// @notice See {IERC4626-totalAssets}
    function totalAssets() public view virtual override returns (uint256) {
        return vaultTVL() - lockedProfit();
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _liquidate(assets);

        // Slippage during liquidation means we might get less than `assets` amount of `_asset`
        assets = Math.min(_asset.balanceOf(address(this)), assets);
        uint256 assetsFee = _getWithdrawalFee(assets);
        uint256 assetsToUser = assets - assetsFee;

        // Burn shares and give user equivalent value in `_asset` (minus withdrawal fees)
        if (caller != owner) _spendAllowance(owner, caller, shares);
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);

        _asset.safeTransfer(receiver, assetsToUser);
        _asset.safeTransfer(governance, assetsFee);
    }

    /*//////////////////////////////////////////////////////////////
                                  FEES
    //////////////////////////////////////////////////////////////*/
    /// @notice Fee charged to vault over a year, number is in bps
    uint256 public managementFee;
    /// @notice  Fee charged on redemption of shares, number is in bps
    uint256 public withdrawalFee;
    uint256 constant SECS_PER_YEAR = 365 days;

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

    /// @dev  Return amount of `asset` to be given to user after applying withdrawal fee
    function _getWithdrawalFee(uint256 tokenAmount) internal view returns (uint256) {
        return tokenAmount.mulDivUp(withdrawalFee, MAX_BPS);
    }
    /*//////////////////////////////////////////////////////////////
                           CAPITAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deposit idle assets into strategies.
     */

    function depositIntoStrategies(uint256 amount) external whenNotPaused onlyRole(HARVESTER) {
        // Deposit entire balance of `_asset` into strategies
        _depositIntoStrategies(amount);
    }

    /*//////////////////////////////////////////////////////////////
                          DETAILED PRICE INFO
    //////////////////////////////////////////////////////////////*/

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
