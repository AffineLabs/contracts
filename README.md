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

### Slither

Install slither with these [instructions](https://github.com/crytic/slither#using-pip). Install [solc-select](https://github.com/crytic/solc-select#quickstart). Update your solc version with:

```sh
solc-select install 0.8.10
solc-select use 0.8.10
```

## Usage

### Compile

Compile the smart contracts:

```sh
$ yarn build
```

Note: `src/test/test.sol` is taken from [dapphub's ds-test repo](https://github.com/dapphub/ds-test/blob/0a5da56b0d65960e6a994d2ec8245e6edd38c248/src/test.sol). We can't install this repo as a package since hardhat expects a package.json file ([issue](https://github.com/nomiclabs/hardhat/issues/1361)). We could fork the repo and add a package.json but this is fine for now.

### Test

Run the Mocha tests:

```sh
$ yarn test-hh path/to/test
```

Run the solidity tests

```sh
$ yarn test-all
```

Update all gas snapshots

```sh
$ yarn snap-all
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

### Running a Script

To run a script run `yarn script <script>`. Pass in the ethereum and polygon networks you want to use with the `-eth` and `-p` flags. The two network names will be in the `ETH_NETWORK` and `POLYGON_NETWORK` environment variables. In the script, use `hre.changeNetwork` to change the current network. If run without the `--no-fork` flag `yarn script` will bring up two hardhat nodes, one which forks the selected ethereum network, and one which forks the selected polygon network.

To deploy the contracts to forked versions of ropsten and mumbai run

```sh
$ yarn script scripts/deploy-all.ts -eth ropsten -p mumbai
```

### Deploying the Contracts

The deploy script can currently be found under `scripts/deploy-all.ts`. It is meant to work with the goerli/mumbai testnets only. **NOTE**: You must manually deploy a forwarder contract and add its address to `scripts/utils/config.ts` before deploying the rest of the contracts. Additionally, you should add the forwarder/usdc contracts to the biconomy dashboard in order to allow meta-transactions with these contracts.

### Validate a contract with etherscan

```
yarn hardhat verify --network <network> <DEPLOYED_CONTRACT_ADDRESS> "Constructor argument 1"
```

## Documentation

You can find documentation (auto-generated from Natspec comments) in the `docs/` folder. You'll need to run `yarn` first to build the docs.
