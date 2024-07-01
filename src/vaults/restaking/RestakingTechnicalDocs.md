# Solidity API

## IUltraLRT

### hasRole

```solidity
function hasRole(bytes32 role, address user) external view returns (bool)
```

### HARVESTER

```solidity
function HARVESTER() external view returns (bytes32)
```

## AffineDelegator

_Delegator contract for stETH on Eigenlayer_

### vault

```solidity
address vault
```

### asset

```solidity
contract ERC20 asset
```

### onlyVaultOrHarvester

```solidity
modifier onlyVaultOrHarvester()
```

Modifier to allow function calls only from the vault or harvester

### onlyVault

```solidity
modifier onlyVault()
```

Modifier to allow function calls only from the vault

### onlyHarvester

```solidity
modifier onlyHarvester()
```

Modifier to allow function calls only from the harvester

### delegate

```solidity
function delegate(uint256 amount) external
```

_Delegate & restake stETH to operator_

### _delegate

```solidity
function _delegate(uint256 amount) internal virtual
```

_Delegate stETH to operator_

### requestWithdrawal

```solidity
function requestWithdrawal(uint256 assets) external
```

Request withdrawal from eigenlayer

_Request withdrawal from eigenlayer_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | Amount to withdraw |

### _requestWithdrawal

```solidity
function _requestWithdrawal(uint256 assets) internal virtual
```

_Request withdrawal from eigenlayer_

### withdraw

```solidity
function withdraw() external virtual
```

_Withdraw stETH from delegator to vault_

### totalLockedValue

```solidity
function totalLockedValue() public view virtual returns (uint256)
```

Get total locked value

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | Total locked value |

### withdrawableAssets

```solidity
function withdrawableAssets() public view virtual returns (uint256)
```

Get withdrawable assets

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | Amount of withdrawable assets |

### queuedAssets

```solidity
function queuedAssets() public view virtual returns (uint256)
```

Get queued assets

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | Amount of queued assets |

## AffineReStaking

### initialize

```solidity
function initialize(address _governance, address _weth) external
```

### _authorizeUpgrade

```solidity
function _authorizeUpgrade(address newImplementation) internal
```

_Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
{upgradeTo} and {upgradeToAndCall}.

Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.

```solidity
function _authorizeUpgrade(address) internal override onlyOwner {}
```_

### GUARDIAN_ROLE

```solidity
bytes32 GUARDIAN_ROLE
```

### APPROVED_TOKEN

```solidity
bytes32 APPROVED_TOKEN
```

### WETH

```solidity
contract IWETH WETH
```

### balance

```solidity
mapping(address => mapping(address => uint256)) balance
```

### depositPaused

```solidity
uint256 depositPaused
```

### whenDepositNotPaused

```solidity
modifier whenDepositNotPaused()
```

### pauseDeposit

```solidity
function pauseDeposit() external
```

### resumeDeposit

```solidity
function resumeDeposit() external
```

### approveToken

```solidity
function approveToken(address _token) external
```

### revokeToken

```solidity
function revokeToken(address _token) external
```

### Deposit

```solidity
event Deposit(uint256 eventId, address depositor, address token, uint256 amount)
```

### depositFor

```solidity
function depositFor(address _token, address _for, uint256 _amount) external
```

### depositETHFor

```solidity
function depositETHFor(address _for) external payable
```

### Withdraw

```solidity
event Withdraw(uint256 eventId, address withdrawer, address token, uint256 amount)
```

### withdraw

```solidity
function withdraw(address _token, uint256 _amount) external
```

### pause

```solidity
function pause() external
```

Pause the contract

### unpause

```solidity
function unpause() external
```

Unpause the contract

## IDelegatorBeacon

### owner

```solidity
function owner() external returns (address)
```

## DelegatorBeacon

_Delegator Beacon contract_

### beacon

```solidity
contract UpgradeableBeacon beacon
```

### blueprint

```solidity
address blueprint
```

### constructor

```solidity
constructor(address _initBlueprint, address governance) public
```

_Constructor_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _initBlueprint | address | Initial blueprint address |
| governance | address | Governance address |

### update

```solidity
function update(address _newBlueprint) public
```

Update the blueprint

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _newBlueprint | address | New blueprint address |

### implementation

```solidity
function implementation() public view returns (address)
```

Get the implementation address

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | address | Implementation address |

## IDelegatorFactory

### createDelegator

```solidity
function createDelegator(address _operator) external returns (address)
```

### vault

```solidity
function vault() external returns (address)
```

## DelegatorFactory

_Delegator Factory contract_

### vault

```solidity
address vault
```

### onlyVault

```solidity
modifier onlyVault()
```

_Modifier to allow function calls only from the vault_

### constructor

```solidity
constructor(address _vault) public
```

_Constructor_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | address | Vault address |

### createDelegator

```solidity
function createDelegator(address _operator) external returns (address)
```

Create a new delegator

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _operator | address | Operator address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | address | Delegator address |

## EigenDelegator

_Delegator contract for stETH on Eigenlayer_

### STRATEGY_MANAGER

```solidity
contract IStrategyManager STRATEGY_MANAGER
```

StrategyManager for Eigenlayer

### DELEGATION_MANAGER

```solidity
contract IDelegationManager DELEGATION_MANAGER
```

DelegationManager for Eigenlayer

### STAKED_ETH_STRATEGY

```solidity
contract IStrategy STAKED_ETH_STRATEGY
```

stETH strategy on Eigenlayer

### withdrawals

```solidity
mapping(bytes32 => uint256) withdrawals
```

### initialize

```solidity
function initialize(address _vault, address _operator) external
```

_Initialize the contract_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | address | Vault address |
| _operator | address | Operator address |

### currentOperator

```solidity
address currentOperator
```

### stETH

```solidity
contract IStEth stETH
```

### queuedShares

```solidity
uint256 queuedShares
```

### _delegate

```solidity
function _delegate(uint256 amount) internal
```

Modifier to allow function calls only from the vault or harvester

_Delegate & restake stETH to operator on Eigenlayer_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to delegate |

### _requestWithdrawal

```solidity
function _requestWithdrawal(uint256 assets) internal
```

Request withdrawal from eigenlayer

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | Amount to withdraw |

### completeWithdrawalRequest

```solidity
function completeWithdrawalRequest(struct WithdrawalInfo[] withdrawalInfo) external
```

Complete withdrawal request

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| withdrawalInfo | struct WithdrawalInfo[] | Withdrawal info |

### recordWithdrawalsRequest

```solidity
function recordWithdrawalsRequest(struct WithdrawalInfo withdrawal) external
```

Record withdrawal request from External requests

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| withdrawal | struct WithdrawalInfo | Withdrawal info |

### withdraw

```solidity
function withdraw() external
```

_Withdraw stETH from delegator to vault_

### withdrawableAssets

```solidity
function withdrawableAssets() public view returns (uint256)
```

Get withdrawable assets

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | withdrawable assets |

### queuedAssets

```solidity
function queuedAssets() public view returns (uint256)
```

Get queued assets

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | queued assets |

### _delegateToOperator

```solidity
function _delegateToOperator() internal
```

_Delegate to operator_

## IDelegator

### requestWithdrawal

```solidity
function requestWithdrawal(uint256 assets) external
```

### checkAssetAvailability

```solidity
function checkAssetAvailability(uint256 assets) external view returns (bool)
```

### delegate

```solidity
function delegate(uint256 amount) external
```

### withdraw

```solidity
function withdraw() external
```

### totalLockedValue

```solidity
function totalLockedValue() external returns (uint256)
```

### withdrawableAssets

```solidity
function withdrawableAssets() external view returns (uint256)
```

### queuedAssets

```solidity
function queuedAssets() external view returns (uint256)
```

## SymDelegatorFactory

_SymDelegator Factory contract_

### vault

```solidity
address vault
```

### onlyVault

```solidity
modifier onlyVault()
```

_Modifier to allow function calls only from the vault_

### constructor

```solidity
constructor(address _vault) public
```

_Constructor_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | address | Vault address |

### createDelegator

```solidity
function createDelegator(address _collateral) external returns (address proxy)
```

Create a new delegator

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _collateral | address | Collateral address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| proxy | address | Delegator address |

## SymbioticDelegator

_Delegator contract for wStETH on Symbiotic_

### collateral

```solidity
contract IDefaultCollateral collateral
```

### initialize

```solidity
function initialize(address _vault, address _collateral) external
```

_Initialize the contract_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | address | Vault address |
| _collateral | address | Collateral address |

### _delegate

```solidity
function _delegate(uint256 amount) internal
```

Delegate & restake wStETH to operator on Symbiotic

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to delegate |

### _requestWithdrawal

```solidity
function _requestWithdrawal(uint256 assets) internal
```

Request withdrawal from Symbiotic

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | Amount to withdraw |

### withdrawableAssets

```solidity
function withdrawableAssets() public view returns (uint256)
```

Get the withdrawable assets

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | withdrawable assets |

### queuedAssets

```solidity
function queuedAssets() public view returns (uint256)
```

Get the queued assets

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | queued assets |

## UltraLRT

UltraLRT is a liquid staking vault that allows users to deposit staked assets and receive shares in return.
The shares can be redeemed for the underlying assets at any time. Vault will delegate the assets to the delegators and harvest the profit.
The vault will also distribute the profits to the holders.

### initialize

```solidity
function initialize(address _governance, address _asset, address _delegatorBeacon, string _name, string _symbol) external
```

Initialize the UltraLRT contract

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _governance | address | The address of the governance contract |
| _asset | address | The address of the asset token |
| _delegatorBeacon | address | The address of the delegator beacon |
| _name | string | The name of the token |
| _symbol | string | The symbol of the token |

### _authorizeUpgrade

```solidity
function _authorizeUpgrade(address newImplementation) internal
```

Upgrade the UltraLRT contract

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newImplementation | address | The address of the new implementation contract |

### maxDeposit

```solidity
function maxDeposit(address) public view virtual returns (uint256)
```

The maximum amount of assets that can be deposited into the vault

_See {IERC4262-maxDeposit}._

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The maximum amount of assets that can be deposited |

### maxMint

```solidity
function maxMint(address) public view virtual returns (uint256)
```

The maximum amount of shares that can be minted

_See {IERC4262-maxMint}._

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The maximum amount of shares that can be minted |

### setDelegatorFactory

```solidity
function setDelegatorFactory(address _factory) external
```

set the delegator factory

_factory must have the vault set to this vault_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _factory | address | The address of the delegator factory |

### setMaxUnresolvedEpochs

```solidity
function setMaxUnresolvedEpochs(uint256 _maxUnresolvedEpochs) external
```

set max unresolved epoch

_delegation of assets will be stopped if the unresolved epoch is greater than the max unresolved epoch_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _maxUnresolvedEpochs | uint256 | The maximum unresolved epoch |

### pause

```solidity
function pause() external
```

Pause the contract

### unpause

```solidity
function unpause() external
```

Unpause the contract

### initialSharesPerAsset

```solidity
function initialSharesPerAsset() public pure virtual returns (uint256)
```

The amount of shares to mint per wei of `asset` at genesis.

### _initialShareDecimals

```solidity
function _initialShareDecimals() internal pure virtual returns (uint8)
```

Each wei of `asset` at genesis is worth 10 ** (initialShareDecimals) shares.

### pauseDeposit

```solidity
function pauseDeposit() external
```

Pause the deposit

### unpauseDeposit

```solidity
function unpauseDeposit() external
```

Unpause the deposit

### deposit

```solidity
function deposit(uint256 assets, address receiver) public returns (uint256)
```

Deposit assets into the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 |  |
| receiver | address | The address of the receiver |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of shares minted |

### mint

```solidity
function mint(uint256 shares, address receiver) public returns (uint256)
```

mint specific amount of shares

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | The amount of shares to mint |
| receiver | address | The address of the receiver |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of assets minted |

### withdraw

```solidity
function withdraw(uint256 assets, address receiver, address owner) public returns (uint256)
```

Withdraw assets from the vault

_See {IERC4262-withdraw}._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | The amount of assets to withdraw |
| receiver | address | The address of the receiver |
| owner | address | The address of the owner |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of shares burned |

### redeem

```solidity
function redeem(uint256 shares, address receiver, address owner) public returns (uint256)
```

Redeem shares from the vault

_See {IERC4262-redeem}._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | The amount of shares to redeem |
| receiver | address | The address of the receiver |
| owner | address | The address of the owner |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | The amount of assets redeemed |

### _withdraw

```solidity
function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal
```

withdraw from the vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| caller | address | The address of the caller |
| receiver | address | The address of the receiver |
| owner | address | The address of the owner |
| assets | uint256 | The amount of assets to withdraw |
| shares | uint256 | The amount of shares to burn |

### canWithdraw

```solidity
function canWithdraw(uint256 assets) public view returns (bool)
```

Check if the withdrawal can be done

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | The amount of assets to withdraw |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if the withdrawal can be done |

### setWithdrawalEscrow

```solidity
function setWithdrawalEscrow(contract WithdrawalEscrowV2 _escrow) external
```

Set the withdrawal escrow

_The escrow must have the vault set to this vault
    @dev existing escrow debt must be zero_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _escrow | contract WithdrawalEscrowV2 | The address of the withdrawal escrow |

### endEpoch

```solidity
function endEpoch() external
```

End the current epoch

_Only the harvester can end the epoch anytime
for other The epoch can only be ended if the last epoch was ended at least `LOCK_INTERVAL` seconds ago_

### liquidationRequest

```solidity
function liquidationRequest(uint256 assets) external
```

Do liquidation request to delegators

_Only the harvester can do the liquidation request_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | The amount of assets to liquidate |

### _liquidationRequest

```solidity
function _liquidationRequest(uint256 assets) internal
```

Do liquidation request to delegators

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | The amount of assets to liquidate |

### delegatorWithdrawRequest

```solidity
function delegatorWithdrawRequest(contract IDelegator delegator, uint256 assets) external
```

Withdraw from speicific delegator

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| delegator | contract IDelegator | The address of the delegator |
| assets | uint256 | The amount of assets to withdraw |

### resolveDebt

```solidity
function resolveDebt() external
```

Resolve the debt

### createDelegator

```solidity
function createDelegator(address _operator) external
```

Create a new delegator

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _operator | address | The address of the operator |

### dropDelegator

```solidity
function dropDelegator(address _delegator) external
```

Drop a delegator

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _delegator | address | The address of the delegator |

### harvest

```solidity
function harvest() external
```

Harvest the profit

### collectDelegatorDebt

```solidity
function collectDelegatorDebt() external
```

Collect the delegator debt

_will withdraw the liquid assets from the delegators_

### withdrawFromDelegator

```solidity
function withdrawFromDelegator(address _delegator) external
```

TODO check for price change on profit and loss

### _getDelegatorLiquidAssets

```solidity
function _getDelegatorLiquidAssets(uint256 requiredVaultAssets) internal
```

Get the delegator liquid assets

_Each time this will check the vault assets, if it meets required assets then it will stop_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requiredVaultAssets | uint256 | The amount of liquid assets required in vault |

### delegateToDelegator

```solidity
function delegateToDelegator(address _delegator, uint256 amount) external
```

Delegate the assets to the delegator

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _delegator | address | The address of the delegator |
| amount | uint256 | The amount of assets to delegate |

### lockedProfit

```solidity
function lockedProfit() public view virtual returns (uint256)
```

Current locked profit amount.

_Profit unlocks uniformly over `LOCK_INTERVAL` seconds after the last harvest_

### totalAssets

```solidity
function totalAssets() public view returns (uint256)
```

Get the total assets

### vaultAssets

```solidity
function vaultAssets() public view returns (uint256)
```

Get the vault liquid assets

### setManagementFee

```solidity
function setManagementFee(uint256 feeBps) external
```

Set the management fee

### setWithdrawalFee

```solidity
function setWithdrawalFee(uint256 feeBps) external
```

Set the withdrawal fee

### getRate

```solidity
function getRate() external view returns (uint256)
```

returns the per share assets

## UltraLRTRouter

_handle deposits from native, weth, stEth, wStEth to vaults_

### weth

```solidity
contract IWETH weth
```

### stEth

```solidity
contract IStEth stEth
```

### wStEth

```solidity
contract IWSTETH wStEth
```

### permit2

```solidity
contract IPermit2 permit2
```

### initialize

```solidity
function initialize(address _governance, address _weth, address _stEth, address _wStEth, address _permit2) external
```

_Initialize the contract_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _governance | address | Governance address |
| _weth | address | WETH address |
| _stEth | address | stETH address |
| _wStEth | address | wstETH address |
| _permit2 | address | Permit2 address |

### _authorizeUpgrade

```solidity
function _authorizeUpgrade(address newImplementation) internal
```

_Upgrade the contract_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newImplementation | address | New implementation address |

### pause

```solidity
function pause() external
```

Pause the contract

### unpause

```solidity
function unpause() external
```

Unpause the contract

### receive

```solidity
receive() external payable
```

Fallback function to receive native tokens

### depositNative

```solidity
function depositNative(address vault, address to) public payable
```

Deposit native tokens to vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| vault | address | Vault address |
| to | address | Receiver address |

### _processNativeDeposit

```solidity
function _processNativeDeposit(uint256 amount, address vault, address to) internal
```

Deposit native tokens to vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |
| vault | address | Vault address |
| to | address | Receiver address |

### _receiveAssetFromThroughPermit2

```solidity
function _receiveAssetFromThroughPermit2(address token, uint256 amount, uint256 nonce, uint256 deadline, bytes signature) internal
```

Receive asset from user through permit2

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | address | Token address |
| amount | uint256 | Amount to receive |
| nonce | uint256 | Nonce |
| deadline | uint256 | Deadline of the permit2 approval |
| signature | bytes | Signature of the permit2 approval |

### depositWeth

```solidity
function depositWeth(uint256 amount, address vault, address to, uint256 nonce, uint256 deadline, bytes signature) external
```

Deposit WETH to vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |
| vault | address | Vault address |
| to | address | Receiver address |
| nonce | uint256 | Nonce |
| deadline | uint256 | Deadline of the permit2 approval |
| signature | bytes | Signature of the permit2 approval |

### depositStEth

```solidity
function depositStEth(uint256 amount, address vault, address to, uint256 nonce, uint256 deadline, bytes signature) external
```

Deposit stETH to vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |
| vault | address | Vault address |
| to | address | Receiver address |
| nonce | uint256 | Nonce |
| deadline | uint256 | Deadline of the permit2 approval |
| signature | bytes | Signature of the permit2 approval |

### depositWStEth

```solidity
function depositWStEth(uint256 amount, address vault, address to, uint256 nonce, uint256 deadline, bytes signature) external
```

Deposit wStETH to vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |
| vault | address | Vault address |
| to | address | Receiver address |
| nonce | uint256 | Nonce |
| deadline | uint256 | Deadline of the permit2 approval |
| signature | bytes | Signature of the permit2 approval |

### _processDepositFromStEth

```solidity
function _processDepositFromStEth(uint256 amount, address vault, address to) internal
```

Process deposit from stEth

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |
| vault | address | Vault address |
| to | address | Receiver address |

### _depositStEthToVault

```solidity
function _depositStEthToVault(uint256 amount, address vault, address to) internal
```

Deposit stEth to vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |
| vault | address | Vault address |
| to | address | Receiver address |

### _depositWStEthToVault

```solidity
function _depositWStEthToVault(uint256 amount, address vault, address to) internal
```

Deposit wStEth to vault

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amount | uint256 | Amount to deposit |
| vault | address | Vault address |
| to | address | Receiver address |

## UltraLRTStorage

### DelegatorInfo

```solidity
struct DelegatorInfo {
  bool isActive;
  uint248 balance;
}
```

### GUARDIAN_ROLE

```solidity
bytes32 GUARDIAN_ROLE
```

### HARVESTER

```solidity
bytes32 HARVESTER
```

### MAX_BPS

```solidity
uint256 MAX_BPS
```

### MAX_DELEGATOR

```solidity
uint256 MAX_DELEGATOR
```

### ST_ETH_TRANSFER_BUFFER

```solidity
uint256 ST_ETH_TRANSFER_BUFFER
```

### depositPaused

```solidity
uint256 depositPaused
```

### STETH

```solidity
contract IStEth STETH
```

### escrow

```solidity
contract WithdrawalEscrowV2 escrow
```

### beacon

```solidity
address beacon
```

### delegatorFactory

```solidity
address delegatorFactory
```

### delegatorAssets

```solidity
uint256 delegatorAssets
```

### managementFee

```solidity
uint256 managementFee
```

Fee charged to vault over a year, number is in bps

### withdrawalFee

```solidity
uint256 withdrawalFee
```

Fee charged on redemption of shares, number is in bps

### lastHarvest

```solidity
uint256 lastHarvest
```

A timestamp representing when the most recent harvest occurred.

_Since the time since the last harvest is used to calculate management fees, this is set
to `block.timestamp` (instead of 0) during initialization._

### maxLockedProfit

```solidity
uint256 maxLockedProfit
```

The amount of profit *originally* locked after harvesting from a strategy

### LOCK_INTERVAL

```solidity
uint256 LOCK_INTERVAL
```

Amount of time in seconds that profit takes to fully unlock. See lockedProfit().

### delegatorQueue

```solidity
contract IDelegator[50] delegatorQueue
```

### delegatorMap

```solidity
mapping(address => struct UltraLRTStorage.DelegatorInfo) delegatorMap
```

### delegatorCount

```solidity
uint256 delegatorCount
```

### lastEpochTime

```solidity
uint256 lastEpochTime
```

### maxUnresolvedEpochs

```solidity
uint256 maxUnresolvedEpochs
```

### whenDepositNotPaused

```solidity
modifier whenDepositNotPaused()
```

## WithdrawalEscrowV2

_Escrow contract for withdrawal requests_

### asset

```solidity
contract ERC20 asset
```

The vault asset.

### vault

```solidity
contract UltraLRT vault
```

The vault this escrow attached to.

### userDebtShare

```solidity
mapping(uint256 => mapping(address => uint256)) userDebtShare
```

### EpochInfo

```solidity
struct EpochInfo {
  uint128 shares;
  uint128 assets;
}
```

### currentEpoch

```solidity
uint256 currentEpoch
```

### resolvingEpoch

```solidity
uint256 resolvingEpoch
```

### totalDebt

```solidity
uint256 totalDebt
```

### epochInfo

```solidity
mapping(uint256 => struct WithdrawalEscrowV2.EpochInfo) epochInfo
```

### constructor

```solidity
constructor(contract UltraLRT _vault) public
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _vault | contract UltraLRT | UltraLRT vault address |

### onlyVault

```solidity
modifier onlyVault()
```

Modifier to allow function calls only from the vault

### onlyGovernance

```solidity
modifier onlyGovernance()
```

Modifier to allow function calls only from the governance

### WithdrawalRequest

```solidity
event WithdrawalRequest(address user, uint256 epoch, uint256 shares)
```

Withdrawal Request event

_will makes things easy to search for each user withdrawal requests_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | user address |
| epoch | uint256 | epoch of the request |
| shares | uint256 | withdrawal vault shares |

### registerWithdrawalRequest

```solidity
function registerWithdrawalRequest(address user, uint256 shares) external
```

Register withdrawal request as debt

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | user address |
| shares | uint256 | amount of vault shares user requested to withdraw |

### endEpoch

```solidity
function endEpoch() external
```

End the epoch

_will be called by the vault after closing a position_

### getDebtToResolve

```solidity
function getDebtToResolve() external view returns (uint256)
```

Get the debt to resolve

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | amount of debt to resolve |

### resolveDebtShares

```solidity
function resolveDebtShares() external
```

resolve the locked shares for current epoch

_This function will be triggered after closing a position
will check for available shares to burn
after resolving vault will send the assets to escrow and burn the share_

### redeemMultiEpoch

```solidity
function redeemMultiEpoch(address user, uint256[] epochs) public returns (uint256 totalAssets)
```

Redeem multiple epochs

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | user address |
| epochs | uint256[] | withdrawal request epochs |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| totalAssets | uint256 | received |

### redeem

```solidity
function redeem(address user, uint256 epoch) public returns (uint256)
```

Redeem withdrawal request

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | address |
| epoch | uint256 | withdrawal request epoch |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | received assets |

### _epochSharesToAssets

```solidity
function _epochSharesToAssets(address user, uint256 epoch) internal view returns (uint256)
```

Convert epoch shares to assets

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | User address |
| epoch | uint256 | withdrawal request epoch |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | converted assets |

### canWithdraw

```solidity
function canWithdraw(uint256 epoch) public view returns (bool)
```

Check if an epoch is completed or not

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| epoch | uint256 | Epoch number |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if epoch is completed |

### withdrawableAssets

```solidity
function withdrawableAssets(address user, uint256 epoch) public view returns (uint256)
```

Get withdrawable assets of a user

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | User address |
| epoch | uint256 | The vault epoch |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | Amount of assets user will receive |

### withdrawableShares

```solidity
function withdrawableShares(address user, uint256 epoch) public view returns (uint256)
```

Get withdrawable shares of a user

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | user address |
| epoch | uint256 | requests epoch |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | amount of shares to withdraw |

### getAssets

```solidity
function getAssets(address user, uint256[] epochs) public view returns (uint256 assets)
```

Get total withdrawable assets of a user for multiple epochs

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | User address |
| epochs | uint256[] | withdrawal request epochs |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| assets | uint256 | total withdrawable assets |

### sweep

```solidity
function sweep(address _asset) external
```

sweep the assets to governance

_only use case in case of emergency_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _asset | address | Asset address |

