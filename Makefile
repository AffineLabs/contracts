# We're just using make as a script runner, these commands are not building targets
.PHONY: test

# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Build & test
build  :; forge build
test   :;  make test-reg && make test-fork-l2 && make test-fork-l1 && make test-fork-anchor
test-reg :; forge test --no-match-contract ".*Fork"
test-fork-l1 :; forge test --match-contract "L1.*Fork" --fork-url \
    "https://eth-goerli.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}" --fork-block-number 6267635
test-fork-l2 :; forge test --match-contract "L2.*Fork" --fork-url "https://polygon-mumbai.g.alchemy.com/v2/${ALCHEMY_POLYGON_KEY}" \
    --fork-block-number 24274280
test-fork-anchor :; forge test --match-contract ".*Anchor.*Fork" --fork-url "https://eth-ropsten.alchemyapi.io/v2/${ALCHEMY_ETH_KEY}" \
    --fork-block-number 11949985
clean  :; forge clean
snapshot :; forge snapshot
