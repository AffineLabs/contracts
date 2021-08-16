#!/usr/bin/env sh

set -x #echo on

NODE_DIR=/root/.bor
DATA_DIR=/root/.bor/data

ADDRESSES=(
  "0x4e80b6AEA58E3Cf1811eA68270322F09B4B6F959"
)

INDEX=$1;
ADDRESS=${ADDRESSES[$INDEX]};

NODE_DIR=/root/.bor
DATA_DIR=/root/.bor/data

docker-compose run --service-ports -d --name bor$INDEX bor$INDEX sh -c "
touch /root/logs/bor.log
bor --datadir $DATA_DIR \
  --port 30303 \
  --bor.heimdall http://heimdall$INDEX:1317 \
  --http --http.addr '0.0.0.0' \
  --ws --ws.port 8546 \
  --http.vhosts '*' \
  --http.corsdomain '*' \
  --http.port 8545 \
  --ipcpath $DATA_DIR/bor.ipc \
  --http.api 'personal,eth,net,web3,txpool,miner,admin,bor' \
  --syncmode 'full' \
  --networkid '15001' \
  --miner.gaslimit '2000000000' \
  --txpool.nolocals \
  --txpool.accountslots '128' \
  --txpool.globalslots '20000' \
  --txpool.lifetime '0h16m0s' \
  --unlock $ADDRESS \
  --keystore $NODE_DIR/keystore \
  --password $NODE_DIR/password.txt \
  --allow-insecure-unlock \
  --mine > /root/logs/bor.log 2>&1 &
tail -f /root/logs/bor.log
"

