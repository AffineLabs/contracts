#!/usr/bin/env sh

set -x #echo on

DATA_DIR=ganache-db

docker-compose run --rm --service-ports --name ganache ganache --hardfork istanbul \
  --blockTime 1 \
  --db /root/data/$DATA_DIR \
  --account 0xeb14d4d6030d2802eb225c3f5c5bbf5042ec805cc9be9184db2a1527c4219744,1000000000000000000000 \
  --gasLimit 8000000 \
  --gasPrice 0 \
  -p 9545 -h 0.0.0.0 
