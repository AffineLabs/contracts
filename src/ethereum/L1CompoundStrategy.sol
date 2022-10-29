// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {ICToken} from "../interfaces/compound/ICToken.sol";
import {IComptroller} from "../interfaces/compound/IComptroller.sol";

import {BaseVault} from "../BaseVault.sol";
import {BaseStrategy} from "../BaseStrategy.sol";

contract L1CompoundStrategy is BaseStrategy, AccessControl {
    using SafeTransferLib for ERC20;

    /// @notice The comptroller
    IComptroller public constant comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    /// @notice Corresponding Compound token for `asset`(e.g. cUSDC for USDC)
    ICToken public immutable cToken;

    /// The compound governance token
    ERC20 public constant comp = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    /// @notice  WETH address. Our swap path is always COMP > WETH > asset
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Uni router for swapping comp to `asset`
    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    bytes32 public constant CLAIMER = keccak256("CLAIMER");

    constructor(BaseVault _vault, ICToken _cToken) BaseStrategy(_vault) {
        cToken = _cToken;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CLAIMER, msg.sender);

        // We can mint cToken and also sell it
        asset.safeApprove(address(cToken), type(uint256).max);
        comp.safeApprove(address(router), type(uint256).max);
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
    function _divest(uint256 assets) internal override returns (uint256) {
        uint256 currAssets = balanceOfAsset();
        uint256 withdrawAmount = currAssets >= assets ? 0 : assets - currAssets;
        if (withdrawAmount == 0) return 0;

        // Withdraw the needed amount
        uint256 amountToRedeem = Math.min(withdrawAmount, cToken.balanceOfUnderlying(address(this)));
        cToken.redeemUnderlying(amountToRedeem);

        uint256 amountToSend = Math.min(assets, balanceOfAsset());
        asset.safeTransfer(address(vault), amountToSend);
        return amountToSend;
    }

    function claimRewards(uint256 minAssetsFromReward) external onlyRole(CLAIMER) {
        ICToken[] memory cTokens = new ICToken[](1);
        cTokens[0] = cToken;
        comptroller.claimComp(address(this), cTokens);
        uint256 compBalance = comp.balanceOf(address(this));

        address[] memory path = new address[](3);
        path[0] = address(comp);
        path[1] = WETH;
        path[2] = address(asset);

        if (compBalance > 0.01e18) {
            router.swapExactTokensForTokens({
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
