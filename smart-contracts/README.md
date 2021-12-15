# Multiplyr Contracts

Uses

- [Hardhat](https://github.com/nomiclabs/hardhat): compile and run the smart contracts on a local development network
- [TypeChain](https://github.com/ethereum-ts/TypeChain): generate TypeScript types for smart contracts
- [Ethers](https://github.com/ethers-io/ethers.js/): renowned Ethereum library and wallet implementation
- [Waffle](https://github.com/EthWorks/Waffle): tooling for writing comprehensive smart contract tests
- [Solhint](https://github.com/protofire/solhint): linter
- [Prettier Plugin Solidity](https://github.com/prettier-solidity/prettier-plugin-solidity): code formatter

This hardhat project is based on [this template](https://github.com/amanusk/hardhat-template).

## Pre Requisites

### Dapp Tools

- Install Dapptools with these [instructions](https://github.com/dapphub/dapptools#installation). **WARNING**: If you are on an M1 mac you may have a ton of trouble. Try to follow this [gist](https://gist.github.com/kendricktan/8463eb9561f30c521fcb10c4c2c95709). If you're still having trouble, try to join the Dapptools [chat](https://dapphub.chat/).

### Foundry (Optional)

You don't actually need to install this, though it can be used as a replacement for dapptools if you're having trouble with nix.

- Install [rust](https://doc.rust-lang.org/cargo/getting-started/installation.html) with

```sh
curl https://sh.rustup.rs -sSf | sh
```

- Install [foundry](https://github.com/gakonst/foundry) with

```sh
cargo install --git https://github.com/gakonst/foundry --bin forge --locked
```

- Install [cast](https://github.com/gakonst/foundry/tree/master/cast) with

```sh
cargo install --git https://github.com/gakonst/foundry --bin cast
```

### Hardhat

- Install nvm with these [instructions](https://github.com/nvm-sh/nvm#install--update-script)
- Install yarn with

```sh
npm install -g yarn
```

- Install the dependencies:

```sh
yarn install
```

- If using vscode, install the [prettier](https://marketplace.visualstudio.com/items?itemName=esbenp.prettier-vscode) and [solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) extensions

## Usage

### Compile

Compile the smart contracts:

```sh
$ dapp build
```

### Test

Run the Mocha tests:

```sh
$ yarn test
```

Run the solidity tests

```sh
$ dapp test
```

### Deploy Vaults

To deploy the Polygon contracts:
`yarn hardhat run scripts/deployPolygon.ts --network <network>`

To deploy the Ethereum contracts:
`yarn hardhat run scripts/deployEth.ts --network <network>`

### Deploy contract to netowrk (requires Mnemonic and infura API key)

```
npx hardhat run --network rinkeby ./scripts/deploy.ts
```

### Validate a contract with etherscan (requires API key)

```
npx hardhat verify --network <network> <DEPLOYED_CONTRACT_ADDRESS> "Constructor argument 1"
```

### Added plugins

- Gas reporter [hardhat-gas-reporter](https://hardhat.org/plugins/hardhat-gas-reporter.html)
- Etherscan [hardhat-etherscan](https://hardhat.org/plugins/nomiclabs-hardhat-etherscan.html)
