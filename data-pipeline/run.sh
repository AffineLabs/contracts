#! /bin/sh

echo "running data collection pipeline"
cd "./data-collection-pipeline/cron_jobs/"

# echo "scrapping asset prices"
# python3 "get_asset_prices.py"

echo "getting coin prices"
python3 "get_crypto_prices.py"

echo "getting amm data"
python3 "get_amm_data.py"

echo "getting lending protocol returns"
python3 "get_lending_returns.py"

echo "running data preprocessing pipeline"
cd "../../data-preprocessing-pipeline/"
python3 "main.py"

exec "$@"
