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

### Foundry

See instructions for installation [here](https://github.com/gakonst/foundry#installation).

### Hardhat

- Install nvm with these [instructions](https://github.com/nvm-sh/nvm#install--update-script). Then run

```sh
nvm use
```

- Install yarn with

```sh
npm install -g yarn
```

- Install the dependencies:

```sh
yarn install
```

- If using vscode, install the [prettier](https://marketplace.visualstudio.com/items?itemName=esbenp.prettier-vscode) and [solidity](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity) extensions

### Slither

Install slither with these [instructions](https://github.com/crytic/slither#using-pip). Install [solc-select](https://github.com/crytic/solc-select#quickstart). Update your solc version with:

```sh
solc-select install 0.8.10
solc-select use 0.8.10
```

## Usage

Create a `.env` file in the root of this repo. It should contain the same variables seen in `.env.example`.

### Compile

Compile the smart contracts:

```sh
$ yarn build
```

### Test

Run the Mocha tests:

```sh
$ yarn test-hh path/to/test
```

Run the solidity tests

```sh
$ yarn test
```

Update all gas snapshots

```sh
$ yarn snap
```

### Lint/Analyze

Run solhint:

```sh
$ yarn lint
```

Run slither:

```sh
$ slither .
```

### Running a Hardhat Script

To run a script run `yarn script <script>`. Pass in the ethereum and polygon networks you want to use with the `-eth` and `-p` flags. The two network names will be in the `ETH_NETWORK` and `POLYGON_NETWORK` environment variables. In the script, use `hre.changeNetwork` to change the current network. If run without the `--no-fork` flag `yarn script` will bring up two hardhat nodes, one which forks the selected ethereum network, and one which forks the selected polygon network.

To deploy the contracts to forked versions of ropsten and mumbai run

```sh
$ yarn script scripts/deploy-all.ts -eth ropsten -p mumbai
```

### Deploying the Contracts

Testnet: `yarn ts-node scripts/deploy.ts -l <1 or 2> -t`
Mainnet: `yarn ts-node scripts/deploy.ts -l <1 or 2>`

Add -b to actually deploy the contracts

### Validate a contract with etherscan

```
yarn hardhat verify --network <network> <DEPLOYED_CONTRACT_ADDRESS> "Constructor argument 1"
```

## Documentation

You can find documentation (auto-generated from Natspec comments) in the `docs/` folder. You'll need to run `yarn` first to build the docs.
