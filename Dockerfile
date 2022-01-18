FROM ubuntu:20.04 AS dapp_env

RUN curl https://deb.nodesource.com/setup_16.x | bash
RUN curl https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

RUN apt-get update && \
    apt-get -y install curl build-essential automake autoconf git jq nodejs yarn

# add user
RUN useradd -d /home/app -m -G sudo app
RUN mkdir -m 0755 /app
RUN chown app /app
RUN mkdir -m 0755 /nix
RUN chown app /nix
USER app
ENV USER app

# install nix
RUN curl -L https://nixos.org/nix/install | sh
ENV PATH="/home/app/.nix-profile/bin:${PATH}"
ENV NIX_PATH="/home/app//.nix-defexpr/channels/"

# install dapptools
RUN curl https://dapp.tools/install | sh

# Set workdir.
WORKDIR /app

# Copy all files to workdir
COPY . .

# Install dependencies
RUN yarn install --ignore-scripts --frozen-lockfile

# Build and test with dapptools
RUN dapp test

# Check gas snapshot
RUN dapp check-snapshot

FROM node:16-alpine AS runtime

# Install git
RUN apk add --no-cache git

# Set a workdir
WORKDIR /app

# Copy package files to workdir
COPY package.json .
COPY yarn.lock .

# Install dependencies
RUN yarn install --ignore-scripts --frozen-lockfile

# Copy all files to workdir
COPY . .

# Generate ABIs (this will compile with hardhat and generate typechain types)
RUN yarn hardhat export-abi

# Check for lint errors
RUN yarn lint

# Check for formatting errors
RUN yarn format

# Run the rebalance script
ENTRYPOINT ["yarn", "script", "./scripts/rebalance.ts"]