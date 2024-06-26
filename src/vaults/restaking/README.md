# Affine ultraLRT Documentation

ultraETH and ultraETHs, collectively ultraLRTs are liquid staking tokens on Eigenlayer and Symbiotic that allow users to deposit their staked Ethereum (stETH) and receive LRT shares in return. These shares can be redeemed for the underlying stETH at any time. The protocol consists of several key components:

## UltraLRT (Liquid Restaking Token)

The [UltraLRT](./UltraLRT.sol) contract is the core of the protocol. It is an ERC-4626 vault that accepts deposits of stETH and issues shares (UltraLRT tokens) in return. The contract manages the delegation of staked assets to various delegators and handles the harvesting and distribution of rewards.

## Flow of Fund Diagram

![ultraETH flow of fund](./affine%20ultraETH%20fundflow.png)


## Key features:

- Accepts deposits of stETH and issues UltraLRT shares
- Delegates staked assets to various delegators
- Harvests and distributes rewards to UltraLRT holders
- Supports withdrawal requests and debt resolution
- Implements fee management (management fee and withdrawal fee)

## Delegators

Delegators are contracts responsible for delegating and restaking the staked assets on different liquid staking protocols like Eigenlayer and Symbiotic. The protocol supports two types of delegators:

1. **EigenDelegator**: Delegates and restakes stETH on the Eigenlayer protocol.
2. **SymbioticDelegator**: Delegates and restakes wstETH (wrapped stETH) on the Symbiotic protocol.

These delegators interact with the respective protocols to delegate the staked assets and manage withdrawal requests.

## Factories and Beacons

The protocol uses the Proxy and Beacon pattern to deploy and upgrade delegators. The following contracts are involved:

- **DelegatorBeacon**: Upgradeable beacon contract for delegators.
- **DelegatorFactory**: Factory contract for creating new delegator instances.
- **SymDelegatorFactory**: Factory contract for creating new Symbiotic delegator instances.

## WithdrawalEscrowV2

The [WithdrawalEscrowV2](./RestakingTechnicalDocs.md#1643%2C4-1643%2C4) contract handles withdrawal requests from users. It registers withdrawal requests as debt and manages the resolution of debt shares when assets become available.

## UltraLRTRouter

The [UltraLRTRouter](./RestakingTechnicalDocs.md#1249%2C4-1249%2C4) contract facilitates deposits into the UltraLRT vault. It supports deposits of native ETH, WETH, stETH, and wstETH by wrapping/unwrapping the assets as needed.

## Other Contracts

- **AffineReStaking**: A contract for managing deposits and withdrawals of various approved tokens.
- **AffineDelegator**: An abstract contract that defines the interface for delegators.
- **UltraLRTStorage**: A storage contract for the UltraLRT contract.

## Key Interfaces

- **IDelegator**: Interface for delegator contracts.
- **IDelegatorBeacon**: Interface for the delegator beacon contract.
- **IDelegatorFactory**: Interface for the delegator factory contract.

This codebase implements a liquid staking protocol that allows users to stake their Ethereum and receive liquid shares in return. The protocol leverages various liquid staking protocols like Eigenlayer and Symbiotic to delegate and restake the staked assets. It provides a unified interface for users to deposit, withdraw, and manage their liquid staking positions.

## Additional Resources
1. To learn how to compile and run this code base read this [repo home documentation](../../../README.md)
2. Auto-generated [technical documentations](./RestakingTechnicalDocs.md)
3. [General user facing documentation](https://affinedefi.gitbook.io/affine-ultraeth)
4. 
