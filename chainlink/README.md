# Chainlink External Adapter for aUSDC and cUSDC prices

This is an external adapter .It can be ran locally, in Docker, AWS Lambda, or GCP Functions.

This code is based on [this template](https://github.com/thodges-gh/CL-EA-Python-Template) from the Chainlink team.

## Install

```
poetry install
```

## Test

```
poetry run pytest
```

# Basic Setup

Note that `--network host` only works on Linux. [Issue](https://github.com/docker/for-mac/issues/2716).

First run `docker network create dev-network` so the containers can recognize each other by name

- Starting the postgres database
  docker run --network dev-network --name postgres-dev -p 5432:5432 -d -e POSTGRES_PASSWORD=secret123 postgres:14.0

- Starting the mumbai chainlink node
  cd ~/.chainlink-mumbai && \
  docker run \
  --network dev-network \
  --name chainlink-mumbai \
  -p 6690:6690 \
  -v ~/.chainlink-mumbai:/chainlink \
  -it \
  --env-file=.env \
  smartcontract/chainlink:0.10.14 local n

# Running

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
