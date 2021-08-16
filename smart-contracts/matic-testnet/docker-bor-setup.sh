#!/usr/bin/env sh

set -x #echo on

for i in {0..0}
do
  NODE_DIR=/root/.bor
  DATA_DIR=/root/.bor/data
  docker-compose run --rm bor$i sh -c "
bor --datadir $DATA_DIR init $NODE_DIR/genesis.json; 
cp $NODE_DIR/nodekey $DATA_DIR/bor/;
cp $NODE_DIR/static-nodes.json $DATA_DIR/bor/;
"
done

echo "Setup done!"