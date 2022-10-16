// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {ICToken} from "../interfaces/compound/ICToken.sol";
import {IComptroller} from "../interfaces/compound/IComptroller.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";

contract L1CompoundStrategy is BaseStrategy, Ownable {
    using SafeTransferLib for ERC20;

    /// @notice The comptroller
    IComptroller public immutable comptroller;
    /// @notice Corresponding Compound token for `asset`(e.g. cUSDC for USDC)
    ICToken public immutable cToken;

    /// The compound governance token
    ERC20 public immutable comp;
    // WETH
    address public immutable wrappedNative;

    /// @notice Sushi/uni router for swapping comp to `asset`
    IUniswapV2Router02 public immutable router;

    constructor(
        BaseVault _vault,
        ICToken _cToken,
        IComptroller _comptroller,
        IUniswapV2Router02 _router,
        ERC20 _comp,
        address _wrappedNative
    ) BaseStrategy(_vault) {
        cToken = _cToken;
        comptroller = _comptroller;

        router = _router;
        comp = _comp;
        wrappedNative = _wrappedNative;
        // Approve transfer on the cToken contract
        asset.safeApprove(address(cToken), type(uint256).max);
        comp.safeApprove(address(router), type(uint256).max);
    }

    /**
     * BALANCES
     *
     */

    function balanceOfComp() public view returns (uint256) {
        return comp.balanceOf(address(this));
    }

    function balanceOfCToken() public view returns (uint256) {
        return cToken.balanceOf(address(this));
    }

    function underlyingBalanceOfCToken() public returns (uint256) {
        return cToken.balanceOfUnderlying(address(this));
    }

    /**
     * INVESTMENT
     *
     */
    function invest(uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _depositWant(amount);
    }

    function _depositWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        require(cToken.mint(amount) == 0, "CompStrat: mint failed");
        return amount;
    }

    /**
     * DIVESTMENT
     *
     */
    function divest(uint256 amount) external override onlyVault returns (uint256) {
        uint256 currAssets = balanceOfAsset();
        uint256 withdrawAmount = currAssets >= amount ? 0 : amount - currAssets;
        _withdrawWant(withdrawAmount, compToAsset(balanceOfComp()) * 95 / 100);

        uint256 amountToSend = Math.min(amount, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    function withdrawAssets(uint256 assets, uint256 minAssetsFromReward) external onlyOwner {
        _withdrawWant(assets, minAssetsFromReward);
    }

    function _withdrawWant(uint256 amount, uint256 minAssetsFromReward) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        comptroller.claimComp(address(this));

        // Sell reward tokens if we have ".01" of them. This only makes sense if the reward token has 18 decimals
        uint256 compBalance = balanceOfComp();
        if (compBalance > 0.01e18) {
            router.swapExactTokensForTokens(
                compBalance, minAssetsFromReward, getTradePath(), address(this), block.timestamp
            );
        }

        uint256 balanceOfUnderlying = underlyingBalanceOfCToken();
        uint256 amountToRedeem = amount;
        if (amountToRedeem > balanceOfUnderlying) {
            amountToRedeem = balanceOfUnderlying;
        }
        return cToken.redeemUnderlying(amountToRedeem);
    }

    /**
     * TVL ESTIMATION
     *
     */
    function totalLockedValue() public override returns (uint256) {
        uint256 balanceExcludingRewards = balanceOfAsset() + underlyingBalanceOfCToken();
        return balanceExcludingRewards + estimatedRewardsInWant();
    }

    function estimatedRewardsInWant() public view returns (uint256) {
        uint256 pendingRewards = comptroller.compAccrued(address(this));
        return compToAsset(balanceOfComp() + pendingRewards);
    }

    function compToAsset(uint256 amountComp) internal view returns (uint256) {
        if (amountComp == 0) return 0;

        uint256[] memory amounts = router.getAmountsOut(amountComp, getTradePath());
        return amounts[amounts.length - 1];
    }

    function getTradePath() internal view returns (address[] memory path) {
        path = new address[](3);
        path[0] = address(comp);
        path[1] = address(wrappedNative);
        path[2] = address(asset);
    }
}
