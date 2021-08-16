#!/usr/bin/env sh

set -x #echo on

DATA_DIR=/home/nadim/matic-testnet/data/ganache-db

ganache-cli --hardfork istanbul \
  --blockTime 1 \
  --db $DATA_DIR \
  --account 0xeb14d4d6030d2802eb225c3f5c5bbf5042ec805cc9be9184db2a1527c4219744,1000000000000000000000 \
  --gasLimit 8000000 \
  --gasPrice 0 \
  -p 9545 -h 0.0.0.0
