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

### Base requirements

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

### Foundry

See instructions for installation [here](https://github.com/gakonst/foundry#installation).

## Usage

- Create a `.env` file in the root of this repo. It should contain the same variables seen in `.env.example`.

- Contact one of the repo admins to get access to the values of the env variables.

### Compile

Compile the smart contracts:

```sh
$ yarn build
```

### Test

Run the foundry local node

```sh
$ foundryup -v nightly-87bc53fc6c874bd4c92d97ed180b949e3a36d78c
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

### Deploying the Contracts

Testnet: `yarn ts-node scripts/deploy.ts -l <1 or 2> -t`
Mainnet: `yarn ts-node scripts/deploy.ts -l <1 or 2>`

Add -b to actually deploy the contracts

## Documentation

You can find documentation in the `docs/` folder.