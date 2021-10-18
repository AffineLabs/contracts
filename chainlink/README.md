# Chainlink External Adapter for aUSDC and cUSDC prices

This is an external adapter. It can be ran locally, in Docker, AWS Lambda, or GCP Functions.

This code is based on [this template](https://github.com/thodges-gh/CL-EA-Python-Template) from the Chainlink team.

## Install

```
poetry install
```

## Test

```
poetry run pytest
```

# Running demo

## Setup Chainlink Node

- Run `docker network create dev-network` so the containers can recognize each other by name

- Start postgres with
  `docker run --network dev-network --name postgres-dev -p 5432:5432 -d -e POSTGRES_PASSWORD=secret123 postgres:14.0`

- Make an alchemy account.

- Create a .env file for each network that you would like to run. If you want to run a kovan node first run `mkdir ~/.chainlink-kovan`. Then put your .env file in ~/.chainlink-kovan. Here's an example .env file:

```
ROOT=/chainlink
LOG_LEVEL=debug
ETH_CHAIN_ID=<chain id>
MIN_OUTGOING_CONFIRMATIONS=2
LINK_CONTRACT_ADDRESS=<insert appropriate contract address>
CHAINLINK_TLS_PORT=0 # This should be non-zero in a production deployment
SECURE_COOKIES=false # Should be true in production
GAS_UPDATER_ENABLED=true
ALLOW_ORIGINS=*
ETH_URL=wss://eth-kovan.alchemy.com/v2/<insert api key>

DATABASE_URL=postgresql://<insert user>:<insert pass>@host:5432/postgres
# 0.01 LINK
MINIMUM_CONTRACT_PAYMENT_LINK_JUELS=10000000000000000
```

- Start the kovan chainlink node (note that if you have two nodes running on localhost, you can only access the GUI for one):

```shell
cd ~/.chainlink-kovan && \
docker run -p 6688:6688 -v ~/.chainlink-kovan:/chainlink -it --env-file=.env \
smartcontract/chainlink:0.10.14 local n
```

- Start the mumbai chainlink node:

```shell
  cd ~/.chainlink-mumbai && \
  docker run \
  --network dev-network \
  --name chainlink-mumbai \
  -p 6690:6690 \
  -v ~/.chainlink-mumbai:/chainlink \
  -it \
  --env-file=.env \
  smartcontract/chainlink:0.10.14 local n
```

- Fund your node’s wallet (go to Keys > Account addresses in your node's GUI) to see your wallet address

You can find the full documentation for running a node [here](https://docs.chain.link/docs/running-a-chainlink-node/).

## Oracle contract setup

- [Deploy oracle](https://docs.chain.link/docs/fulfilling-requests/#deploy-your-own-oracle-contract). You’ll need to pass the address of link on the network that you’re deploying on.
- [Add node to oracle contract](https://docs.chain.link/docs/fulfilling-requests/#add-your-node-to-the-oracle-contract). This transaction must be called by the deployer of the oracle.

## Adding a job to your Chainlink node

- [Add bridge](https://docs.chain.link/docs/node-operators/). You'll need to put your real IP address in the bridge url.

- Deploy client contract
  - Use job id from job creation step above)
  - set chainlink address and oracle address correctly

## Requesting data

- Call the request function (e.g. requestDepositTokenPrice).

# Running External Adapter

## Run with Docker

Build the image

```
docker build . -t cl-ea
```

Run the container

```
docker run -it -p 8080:8080 cl-ea
```

## Run with Serverless (the below is out of date)

### Create the zip

```bash
pipenv lock -r > requirements.txt
pipenv run pip install -r requirements.txt -t ./package
pipenv run python -m zipfile -c cl-ea.zip main.py adapter.py bridge.py ./package/*
```

### Install to AWS Lambda

- In Lambda Functions, create function
- On the Create function page:
  - Give the function a name
  - Use Python 3.7 for the runtime
  - Choose an existing role or create a new one
  - Click Create Function
- Under Function code, select "Upload a .zip file" from the Code entry type drop-down
- Click Upload and select the `cl-ea.zip` file
- Change the Handler to `main.lambda_handler`
- Save

#### To Set Up an API Gateway

An API Gateway is necessary for the function to be called by external services.

- Click Add Trigger
- Select API Gateway in Trigger configuration
- Under API, click Create an API
- Choose REST API
- Select the security for the API
- Click Add
- Click the API Gateway trigger
- Click the name of the trigger (this is a link, a new window opens)
- Click Integration Request
- Uncheck Use Lamba Proxy integration
- Click OK on the two dialogs
- Return to your function
- Remove the API Gateway and Save
- Click Add Trigger and use the same API Gateway
- Select the deployment stage and security
- Click Add

### Install to Google Cloud Funcions

- In Functions, create a new function
- Use HTTP for the Trigger
- Optionally check the box to allow unauthenticated invocations
- Choose ZIP upload under Source Code
- Use Python 3.9 for the runtime
- Click Browse and select the `cl-ea.zip` file
- Select a Storage Bucket to keep the zip in
- Function to execute: `gcs_handler`
- Click Create
