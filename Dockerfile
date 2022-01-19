FROM node:16-alpine

# Install git
RUN apk add --no-cache git

# Set a workdir
WORKDIR /app

# Copy all files to workdir
COPY . .

# Install dependencies, build contracts, generate abis, generate typings
# Don't run lyfecycle scipts as that depends on Dapptools
RUN yarn --frozen-lockfile --ignore-scripts

# Run the rebalance script
ENTRYPOINT ["yarn", "script", "./scripts/rebalance.ts"]