FROM ubuntu:20.04 AS dapp_env

RUN apt-get update && \
    apt-get -y install curl build-essential automake autoconf git jq

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

# Build contracts with dapptools
RUN dapp build

# Run dapptools unit tests
RUN dapp test


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

# Copy dapptools build outputs
RUN mkdir /app/out
COPY --from=dapp_env /app/out /app/out

# Generate ABIs
RUN yarn abi

# Generate Typechain types
RUN yarn types

# Run the rebalance script
ENTRYPOINT ["yarn", "script", "./scripts/rebalance.ts"]