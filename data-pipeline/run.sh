#! /bin/sh

echo "running data collection pipeline"
cd "./data-collection-pipeline/cron_jobs"
python3 "get_asset_prices.py"
python3 "get_crypto_prices.py"
python3 "get_amm_data.py"
python3 "get_lending_returns.py"

echo "running data preprocessing pipeline"
cd "../../data-preprocessing-pipeline/"
python3 "main.py"

exec "$@"
