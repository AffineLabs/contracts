#!/usr/bin/env sh

set -x #echo on

# private key to deploy contracts
export PRIVATE_KEY=0xeb14d4d6030d2802eb225c3f5c5bbf5042ec805cc9be9184db2a1527c4219744
export MNEMONIC=0xeb14d4d6030d2802eb225c3f5c5bbf5042ec805cc9be9184db2a1527c4219744

# export heimdall id
export HEIMDALL_ID=heimdall-15001

# cd matic contracts repo
cd /home/nadim/matic-testnet/code/contracts

# bor contracts are deployed on child chain
npm run truffle:migrate:dev:bor -- --reset -f 5 --to 5
