#!/usr/bin/env sh

PRIV_VALIDATOR_STATE="{
  \"height\": \"0\",
  \"round\": \"0\",
  \"step\": 0
}"

# stop and remove docker containers
docker-compose down

# clean repo
for i in {0..0}
do
  NODE_DIR=$PWD/devnet/node$i
  rm -rf $NODE_DIR/bor/data/bor $NODE_DIR/heimdalld/config/write-file-* $NODE_DIR/heimdalld/data $NODE_DIR/heimdalld/config/addrbook.json $NODE_DIR/heimdalld/bridge/storage
  mkdir -p $NODE_DIR/heimdalld/data
  echo $PRIV_VALIDATOR_STATE > $NODE_DIR/heimdalld/data/priv_validator_state.json
done

rm -rf logs
