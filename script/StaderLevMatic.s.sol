// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SlippageUtils} from "src/libs/audited/SlippageUtils.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EthVaultV2} from "src/vaults/EthVaultV2.sol";
import {Vault} from "src/vaults/VaultV2.sol";
import {Router} from "src/vaults/cross-chain-vault/router/audited/Router.sol";

import {StaderLevMaticStrategy, IWMATIC} from "src/strategies/StaderLevMaticStrategy.sol";
import {LevMaticXLoopStrategy, IWMATIC} from "src/strategies/LevMaticXLoopStrategy.sol";
import {AffineVault} from "src/vaults/AffineVault.sol";

import {Base} from "./Base.sol";
import {Router, IWETH} from "src/vaults/cross-chain-vault/router/audited/Router.sol";

/* solhint-disable reason-string, no-console */

contract TestLevLoopMaticXStrategy is LevMaticXLoopStrategy {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for IWMATIC;
    using FixedPointMathLib for uint256;
    using SlippageUtils for uint256;

    constructor(AffineVault _vault, address[] memory strategists) LevMaticXLoopStrategy(_vault, strategists) {}

    function testDivest(uint256 amount) external returns (uint256) {
        uint256 tvl = totalLockedValue();
        uint256 repayAmount =
            amount < tvl ? WMATIC.balanceOf(address(this)).mulDivDown(amount, tvl) : WMATIC.balanceOf(address(this));

        uint256 postRes = WMATIC.balanceOf(address(this)) - repayAmount;

        AAVE.repay(address(WMATIC), repayAmount, 2, address(this));
        uint256 stMaticToRedeem;
        uint256 amountReceived;
        for (uint256 i = 1; i <= iCycle; i++) {
            uint256 exCollateral = _collateral() - _debt().mulDivUp(MAX_BPS, borrowBps);
            (stMaticToRedeem,,) = STADER.convertMaticToMaticX(exCollateral);
            AAVE.withdraw(address(MATICX), stMaticToRedeem, address(this));
            amountReceived = _swapMaticXToMatic(MATICX.balanceOf(address(this)));
            if (i < iCycle) {
                AAVE.repay(address(WMATIC), amountReceived, 2, address(this));
            }
        }
        uint256 unlockedAssets = WMATIC.balanceOf(address(this)) - postRes;
        // sending it to deployer
        WMATIC.safeTransfer(0x4E283AbD94aee0a5a64A582def7b22bba60576d8, unlockedAssets);
        return unlockedAssets;
    }
}

library polygonStader {
    function _getStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    function deployWmaticVault(address governance, address wmatic) internal returns (EthVaultV2) {
        // Deploy implementation
        EthVaultV2 impl = new EthVaultV2();

        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(Vault.initialize, (governance, wmatic, "Stader 6x Lev Matic", "6xLevMatic"));
        console2.logBytes(initData);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        // Check that values were set correctly.
        EthVaultV2 vault = EthVaultV2(payable(address(proxy)));
        require(vault.governance() == governance);
        require(address(vault.asset()) == wmatic);
        return vault;
    }
}

contract Deploy is Script, Base {
    address governance = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
    address wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address wmaticVaultAddr = 0x5cfD50De188a36d2089927c5a14E143DC65Af780;

    function _start() internal {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        console2.log("dep %s", deployer);
        vm.startBroadcast(deployer);
    }

    function runWmatic() external {
        _start();
        EthVaultV2 vault = polygonStader.deployWmaticVault(governance, wmatic);
        console2.log("Wmatic denominated vault addr:", address(vault));
        EthVaultV2.Number memory price = vault.detailedPrice();
        console2.log("price: %s", price.num);
    }

    function depStaderStrat() public {
        _start();
        AffineVault vault = AffineVault(wmaticVaultAddr);

        require(address(vault.asset()) == wmatic, "Invalid asset");

        StaderLevMaticStrategy strategy = new StaderLevMaticStrategy(vault, polygonStader._getStrategists());

        console2.log("strategy address %s", address(strategy));

        require(address(strategy.asset()) == address(vault.asset()), "Invalid asset");
    }

    function investTestMatic() public {
        _start();
        IWMATIC iWmatic = IWMATIC(payable(wmatic));
        iWmatic.deposit{value: 2 * 1e18}();

        console2.log("wmatic balance ", iWmatic.balanceOf(address(0x4E283AbD94aee0a5a64A582def7b22bba60576d8)));

        StaderLevMaticStrategy strategy = StaderLevMaticStrategy(payable(0x468798b5C389CD822cF4b2E1431f09222F606399));

        iWmatic.approve(address(strategy), 2 * 1e18);

        strategy.invest(2 * 1e18);

        console2.log("TVL %s", strategy.totalLockedValue());
    }

    function routerDeploy() external {
        _start();
        Router router = new Router("affine-polygon-router", IWETH(wmatic));
        console2.log("router weth: %s", address(router.weth()));
    }

    function depTest6xStaderStrat() public {
        _start();
        AffineVault vault = AffineVault(wmaticVaultAddr);

        require(address(vault.asset()) == wmatic, "Invalid asset");

        TestLevLoopMaticXStrategy strategy = new TestLevLoopMaticXStrategy(vault, polygonStader._getStrategists());

        console2.log("strategy address %s", address(strategy));

        require(address(strategy.asset()) == address(vault.asset()), "Invalid asset");
    }

    function dep6xStaderStrat() public {
        _start();
        AffineVault vault = AffineVault(0x78589e94401647C1b9A807feb7EAA162e9e65bBD);

        require(address(vault.asset()) == wmatic, "Invalid asset");

        LevMaticXLoopStrategy strategy = new LevMaticXLoopStrategy(vault, polygonStader._getStrategists());

        console2.log("strategy address %s", address(strategy));

        require(address(strategy.asset()) == address(vault.asset()), "Invalid asset");
    }

    function investTestMaticV2() public {
        _start();
        IWMATIC iWmatic = IWMATIC(payable(wmatic));
        iWmatic.deposit{value: 2 * 1e18}();

        console2.log("wmatic balance ", iWmatic.balanceOf(address(0x4E283AbD94aee0a5a64A582def7b22bba60576d8)));

        TestLevLoopMaticXStrategy strategy =
            TestLevLoopMaticXStrategy(payable(0x6Df71D1dEaD38Bb36ca4a82FCEc4421CFf279a9B));

        iWmatic.approve(address(strategy), 2 * 1e18);

        strategy.invest(2 * 1e18);

        console2.log("TVL %s", strategy.totalLockedValue());
    }
}
