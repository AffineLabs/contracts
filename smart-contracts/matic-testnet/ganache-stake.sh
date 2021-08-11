#!/usr/bin/env sh

set -x #echo on

# stake
STAKE=10000

# fee
FEE=2000

# cd matic contracts
cd /home/nadim/matic-testnet/code/contracts

# root contracts are deployed on base chain

npm run truffle exec scripts/stake.js -- --network development 0x4e80b6AEA58E3Cf1811eA68270322F09B4B6F959 0x5c3e1db390f4847d2349b74a3762d071fdfce9e14b8916cef9b27f1912dad461155c14812f64925291fbdc1c3f76569d1fe295ec95dcbf26453e36a9d9161f60 $STAKE $FEE
sleep 10
