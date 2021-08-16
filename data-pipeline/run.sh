#! /bin/sh

echo "running data collection pipeline"
python3 "./data-collection-pipeline/cron_jobs/get_asset_prices.py"
python3 "./data-collection-pipeline/cron_jobs/get_crypto_prices.py"
python3 "./data-collection-pipeline/cron_jobs/get_amm_data.py"
python3 "./data-collection-pipeline/cron_jobs/get_lending_returns.py"

echo "running data preprocessing pipeline"
python3 "./data-preprocessing-pipeline/main.py"

exec "$@"