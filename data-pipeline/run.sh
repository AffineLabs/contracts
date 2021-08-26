#! /bin/sh

echo "running data collection pipeline"
cd "./data-collection-pipeline/cron_jobs/"
mkdir "test_results"
python3 "get_asset_prices.py"
python3 "get_crypto_prices.py"

echo "running data preprocessing pipeline"
cd "../../data-preprocessing-pipeline/"
python3 "main.py"

exec "$@"