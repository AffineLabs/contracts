FROM nixos/nix as nix_env

# Install dapptools.
RUN curl https://dapp.tools/install | sh

# Set a workdir.
WORKDIR /app

# Copy all files to workdir.
COPY . .

# Build contracts with dapptools.
RUN dapp build


FROM node:16-alpine as runtime

# Install git.
RUN apk add --no-cache git

# Set a workdir.
WORKDIR /app

# Copy package files to workdir.
COPY package.json .
COPY yarn.lock .

# Install dependencies.
RUN yarn install --ignore-scripts --frozen-lockfile

# Copy all files to workdir.
COPY . .
# Copy dapptools build outputs.
RUN mkdir /app/out
COPY --from=nix_env /app/out /app/out

# Generate ABIs.
RUN yarn abi

# Generate Typechain types.
RUN yarn types

# Run the rebalance script.
ENTRYPOINT ["yarn", "script", "./scripts/rebalance.ts"]