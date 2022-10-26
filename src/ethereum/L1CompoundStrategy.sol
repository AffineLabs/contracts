// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {ICToken} from "../interfaces/compound/ICToken.sol";
import {IComptroller} from "../interfaces/compound/IComptroller.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";

contract L1CompoundStrategy is BaseStrategy {
    using SafeTransferLib for ERC20;

    /// @notice The COMPTROLLER
    IComptroller public constant COMPTROLLER = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    /// @notice Corresponding Compound token for `asset`(e.g. cUSDC for USDC)
    ICToken public immutable cToken;

    /// The compound governance token
    ERC20 public constant COMP = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    /// @notice  WETH address. Our swap path is always COMP > WETH > asset
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Uni ROUTER for swapping COMP to `asset`
    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    constructor(BaseVault _vault, ICToken _cToken) BaseStrategy(_vault) {
        cToken = _cToken;

        // We can mint cToken and also sell it
        asset.safeApprove(address(cToken), type(uint256).max);
        COMP.safeApprove(address(ROUTER), type(uint256).max);
    }

    /**
     * INVESTMENT
     *
     */
    function _afterInvest(uint256 amount) internal override {
        if (amount == 0) return;
        require(cToken.mint(amount) == 0, "CompStrat: mint failed");
    }

    /**
     * DIVESTMENT
     *
     */
    function divest(uint256 amount) external override onlyVault returns (uint256) {
        uint256 currAssets = balanceOfAsset();
        uint256 withdrawAmount = currAssets >= amount ? 0 : amount - currAssets;
        if (withdrawAmount == 0) return 0;

        // Withdraw the needed amount
        uint256 amountToRedeem = Math.min(withdrawAmount, cToken.balanceOfUnderlying(address(this)));
        cToken.redeemUnderlying(amountToRedeem);

        uint256 amountToSend = Math.min(amount, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    function claimRewards(uint256 minAssetsFromReward) external onlyRole(vault.STRATEGIST()) {
        COMPTROLLER.claimComp(address(this));
        uint256 compBalance = COMP.balanceOf(address(this));

        address[] memory path = new address[](3);
        path[0] = address(COMP);
        path[1] = WETH;
        path[2] = address(asset);

        if (compBalance > 0.01e18) {
            ROUTER.swapExactTokensForTokens({
                amountIn: compBalance,
                amountOutMin: minAssetsFromReward,
                path: path,
                to: address(this),
                deadline: block.timestamp
            });
        }
    }

    /**
     * TVL ESTIMATION
     *
     */
    function totalLockedValue() public override returns (uint256) {
        return balanceOfAsset() + cToken.balanceOfUnderlying(address(this));
    }
}
