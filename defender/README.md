# Defender Autotask for Alpine Protocol

## Setup

The `tsconfig.json` sets the configuration for the typescript compiler to emit the javascript code to be used in the Defender Autotask.

1. Run `yarn build` (or simply `tsc`) to compile the script in [`src/index.ts`](src/index.ts)
1. Copy the generated code from `dist/index.js`, and paste it into an Autotask.

## Running Locally

You can run the scripts locally, instead of in an Autotask, via a Defender Relayer. Create a Defender Relayer on mainnet, write down the API key and secret, and create a `.env` file in this folder with values indicated in `.env.example` file.

Then run `yarn start`, which will run the typescript code using `ts-node`, and connecting to your Defender Relayer via the HTTP API.
