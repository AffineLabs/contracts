// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {Script, console2} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StrategyVault} from "src/vaults/locked/StrategyVault.sol";
import {MockEpochStrategy} from "src/testnet/MockEpochStrategy.sol";
import {SSVDeltaNeutralLp} from "src/strategies/SSVDeltaNeutralLp.sol";
import {LpInfo, LendingInfo} from "src/strategies/DeltaNeutralLp.sol";
import {WithdrawalEscrow} from "src/vaults/locked/WithdrawalEscrow.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {ILendingPool} from "src/strategies/DeltaNeutralLp.sol";
import {IMasterChef} from "src/interfaces/sushiswap/IMasterChef.sol";
import {AggregatorV3Interface} from "src/interfaces/AggregatorV3Interface.sol";

import {WithdrawalEscrow} from "src/vaults/locked/WithdrawalEscrow.sol";
import {MockEpochStrategy} from "src/testnet/MockEpochStrategy.sol";
import {DummyEpochStrategy} from "src/testnet/DummyEpochStrategy.sol";
import {DegenVault} from "src/vaults/custom/DegenVault.sol";

/* solhint-disable reason-string, no-console */

library SSV {
    function _getStrategists() internal pure returns (address[] memory strategists) {
        strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
    }

    function _getEthMainNetUSDCAddr() internal pure returns (address) {
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    /// @dev WETH/USDC on sushiswap
    function deployEthSSVSushiUSDCStrategy(
        StrategyVault vault,
        uint256 assetToDepositRatioBps,
        uint256 collateralToBorrowRatioBps
    ) internal returns (SSVDeltaNeutralLp strategy) {
        strategy = new SSVDeltaNeutralLp(
            vault,
            LendingInfo({
                pool: ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
                borrow: ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // weth
                priceFeed: AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419), // eth-usdc feed
                assetToDepositRatioBps: assetToDepositRatioBps,
                collateralToBorrowRatioBps: collateralToBorrowRatioBps
            }),
            LpInfo({
                router: IUniswapV2Router02(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F),
                masterChef: IMasterChef(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd), // MasterChef
                masterChefPid: 1, // Masterchef PID for WETH/USDC
                useMasterChefV2: false, // use MasterChefV2 interface
                sushiToken: ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2),
                pool: IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640) // 5 bps pool (gets most volume)
            }),
            _getStrategists()
        );
    }

    function deployEthSSVSushiUSDC(address deployer) internal returns (StrategyVault sVault) {
        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(StrategyVault.initialize, (deployer, _getEthMainNetUSDCAddr(), "SSV", "SSV"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        sVault = StrategyVault(address(proxy));

        console2.log("Vault addr:", address(sVault));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), deployer));
        require(sVault.asset() == _getEthMainNetUSDCAddr());

        SSVDeltaNeutralLp strategy = deployEthSSVSushiUSDCStrategy(sVault, 5714, 7500);

        // add strategy
        // Add strategy to vault
        sVault.setStrategy(strategy);
        require(sVault.strategy() == strategy);

        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);

        // set escrow
        sVault.setDebtEscrow(escrow);
        console2.log("Strategy addr:", address(strategy));
        console2.log("Escrow addr:", address(escrow));
    }
}

contract Deploy is Script {
    function mainnet() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // Deploy vault
        StrategyVault impl = new DegenVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (
                0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e,
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                "Affine High Yield LP - USDC-wETH",
                "affineSushiUsdcWeth"
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e));
        require(sVault.asset() == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        // Price must be 100 usdc
        require(sVault.detailedPrice().num == 100e6, "Price should be 100e6");

        // Deploy strategy
        SSV.deployEthSSVSushiUSDCStrategy(sVault, 5714, 7500);

        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);
    }

    function deployEscrow() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        StrategyVault sVault = StrategyVault(0x61A18EE9d6d51F838c7e50dFD750629Fd141E944);
        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);
    }

    function run() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // Deploy vault
        StrategyVault impl = new StrategyVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize, (deployer, 0xb465fBFE1678fF41CD3D749D54d2ee2CfABE06F3, "Test Sushi SSV", "tSSV")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));

        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), deployer));
        require(sVault.asset() == 0xb465fBFE1678fF41CD3D749D54d2ee2CfABE06F3);

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = deployer;
        MockEpochStrategy strategy = new MockEpochStrategy(sVault, strategists);

        // Add strategy to vault
        sVault.setStrategy(strategy);
        require(sVault.strategy() == strategy);

        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);
        sVault.setDebtEscrow(escrow);
        require(sVault.debtEscrow() == escrow);
    }

    function runTestV2() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        // Deploy vault
        StrategyVault impl = new DegenVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (
                0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e,
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                "Affine High Yield LP",
                "affineDegen"
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e));
        require(sVault.asset() == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        // Price must be 100 usdc
        require(sVault.detailedPrice().num == 100e6, "Price should be 100e6");

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        DummyEpochStrategy strategy = new DummyEpochStrategy(sVault, strategists);

        require(address(strategy.vault()) == address(sVault));
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
    }

    function runExpV2Test() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address gov = deployer;

        // Deploy vault
        StrategyVault impl = new DegenVault();
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(
            StrategyVault.initialize,
            (gov, 0xb465fBFE1678fF41CD3D749D54d2ee2CfABE06F3, "Affine High Yield LP", "affineDegen")
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), gov));
        require(sVault.asset() == 0xb465fBFE1678fF41CD3D749D54d2ee2CfABE06F3);

        // Price must be 100 usdc
        require(sVault.detailedPrice().num == 100e6, "Price should be 100e6");

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        DummyEpochStrategy strategy = new DummyEpochStrategy(sVault, strategists);

        require(address(strategy.vault()) == address(sVault));
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));

        sVault.setStrategy(strategy);
        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);
        sVault.setDebtEscrow(escrow);
        require(sVault.debtEscrow() == escrow);
    }

    function runExpV2Main() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address gov = 0x4B21438ffff0f0B938aD64cD44B8c6ebB78ba56e;
        address asset = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // Deploy vault
        StrategyVault impl = new DegenVault();
        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(StrategyVault.initialize, (gov, asset, "Affine High Yield LP", "affineDegen"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), gov));
        require(sVault.asset() == asset);

        // Price must be 100 usdc
        require(sVault.detailedPrice().num == 100e6, "Price should be 100e6");

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        DummyEpochStrategy strategy = new DummyEpochStrategy(sVault, strategists);

        require(address(strategy.vault()) == address(sVault));
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
        // sVault.setStrategy(strategy);

        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);

        // sVault.setDebtEscrow(escrow);
        // require(sVault.debtEscrow() == escrow);
    }

    function runExpV2Poly() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address gov = 0xE73D9d432733023D0e69fD7cdd448bcFFDa655f0;
        address asset = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

        // Deploy vault
        StrategyVault impl = new DegenVault();
        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(StrategyVault.initialize, (gov, asset, "Affine High Yield LP", "affineDegen"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), gov));
        require(sVault.asset() == asset);

        // Price must be 100 usdc
        require(sVault.detailedPrice().num == 100e6, "Price should be 100e6");

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        DummyEpochStrategy strategy = new DummyEpochStrategy(sVault, strategists);

        require(address(strategy.vault()) == address(sVault));
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
        // sVault.setStrategy(strategy);

        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);

        // sVault.setDebtEscrow(escrow);
        // require(sVault.debtEscrow() == escrow);
    }

    function runExpV2PolyTest() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        address gov = deployer;
        address asset = 0x8f7116CA03AEB48547d0E2EdD3Faa73bfB232538;

        // Deploy vault
        StrategyVault impl = new DegenVault();
        // Initialize proxy with correct data
        bytes memory initData =
            abi.encodeCall(StrategyVault.initialize, (gov, asset, "Affine High Yield LP", "affineDegen"));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        StrategyVault sVault = StrategyVault(address(proxy));
        require(sVault.hasRole(sVault.DEFAULT_ADMIN_ROLE(), gov));
        require(sVault.asset() == asset);

        // Price must be 100 usdc
        require(sVault.detailedPrice().num == 100e6, "Price should be 100e6");

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d;
        DummyEpochStrategy strategy = new DummyEpochStrategy(sVault, strategists);

        require(address(strategy.vault()) == address(sVault));
        require(strategy.hasRole(strategy.STRATEGIST_ROLE(), 0x47fD0834DD8b435BbbD7115bB7d3b3120dD0946d));
        sVault.setStrategy(strategy);

        // Deploy Escrow
        WithdrawalEscrow escrow = new WithdrawalEscrow(sVault);
        require(escrow.vault() == sVault);

        sVault.setDebtEscrow(escrow);
        require(sVault.debtEscrow() == escrow);
    }

    function runMainNet() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);
        console2.log("Deployer addr", deployer);
        SSV.deployEthSSVSushiUSDC(deployer);
    }

    function deployStrategy() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);

        // Deploy strategy
        address[] memory strategists = new address[](1);
        strategists[0] = deployer;
        MockEpochStrategy strategy = new MockEpochStrategy(sVault, strategists);

        // Add strategy to vault
        sVault.setStrategy(strategy);
        require(sVault.strategy() == strategy);
    }

    function mint() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);
        MockEpochStrategy strategy = MockEpochStrategy(address(sVault.strategy()));

        console2.log("strategy: %s", address(strategy));

        strategy.mint(100);
    }

    function lock() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);
        MockEpochStrategy strategy = MockEpochStrategy(address(sVault.strategy()));

        console2.log("Current epoch: ", sVault.epoch());
        console2.log("Epoch ended: %s", sVault.epochEnded());
        strategy.beginEpoch();
    }

    function unlock() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        StrategyVault sVault = StrategyVault(0x3E84ac8696CB58A9044ff67F8cf2Da2a81e39Cf9);
        MockEpochStrategy strategy = MockEpochStrategy(address(sVault.strategy()));

        console2.log("Current epoch: ", sVault.epoch());
        console2.log("Epoch ended: %s", sVault.epochEnded());
        strategy.endEpoch();
    }

    /**
     * @dev deployment date: June 23, 23
     * @dev purpose: Upgrade implementation of polygon degen vault
     * @dev implementation add: 0x7EBD7e6ADe7Dcb3f12b53691e0cC285b06Fb4094
     */
    function deployNewPolygonDegenDegenVaultV2() external {
        (address deployer,) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
        vm.startBroadcast(deployer);

        DegenVault sVault = new DegenVault();
        console2.log("deployer %s", deployer);
        console2.log("Vault address %s", address(sVault));
    }
}
