# Affine Protocol

This repository contains the core smart contracts for the Affine Protocol.

## Licensing

The primary license for Affine Protocol is the Business Source License 1.1, see [LICENSE](LICENSE).

## Governance

The Protocol currently controls access to these two multi-sig addresses:

- Polygon: 0x47C43be6e8B0a171eab00e42226aE2d1cEFC00fB
- Ethereum: 0x67Ec3Bb25a5DB6eB7Ba74f6C0b2bA193A3983FB8

## Branches and Deployment

The `master` branch is what is currently deployed. The last audit was conducted against the contents of the branch `audit-v4`.

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
solc-select install 0.8.16
solc-select use 0.8.16
```

### Husky

Install pre-commit hooks: `yarn husky install`

## Usage

Create a `.env` file in the root of this repo. It should contain the same variables seen in `.env.example`.

### Compile

Compile the smart contracts:

```sh
$ yarn build
```

### Test

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

To run a script run `yarn script <script>`. Pass in the ethereum and polygon networks you want to use with the `-eth` and `-p` flags. The two network names will be in the `ETH_NETWORK` and `POLYGON_NETWORK` environment variables. In the script, use `hre.changeNetwork` to change the current network. If run without the `--no-fork` flag `yarn script` will bring up two anvil nodes, one which forks the selected ethereum network, and one which forks the selected polygon network. If run with `--relay` then OZ Relayer will be used to send any transactions.

To run the rebalance script against testnets:

```sh
$ yarn script scripts/rebalance.ts -eth goerli -p mumbai --no-fork
```

### Deploying the Contracts

Testnet: `yarn ts-node scripts/deploy.ts -l <1 or 2> -t`
Mainnet: `yarn ts-node scripts/deploy.ts -l <1 or 2>`

Add -b to actually deploy the contracts

## Documentation

You can find documentation (auto-generated from Natspec comments) in the `docs/` folder. You'll need to run `yarn hardhat dodoc` first to build the docs.
