FROM node:16-alpine

# Install git
RUN apk add --no-cache git

# Set a workdir
WORKDIR /app

# Copy all files to workdir
COPY . .

# Install dependencies, build contracts, generate abis, generate typings
RUN yarn --frozen-lockfile

# Run the rebalance script
ENTRYPOINT ["yarn", "script", "./scripts/rebalance.ts"]