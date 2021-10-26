#! /bin/sh

echo "running data collection pipeline"
cd "./data_collection_pipeline/cron_jobs/"

# echo "scrapping asset prices"
# python3 "get_asset_prices.py"

# echo "getting coin prices"
# python3 "get_crypto_prices.py"

# echo "getting amm data"
# python3 "get_amm_data.py"

# echo "getting lending protocol returns"
# python3 "get_lending_returns.py"

# echo "running data preprocessing pipeline"
# cd "../../data_preprocessing_pipeline/"
# python3 "main.py"

echo "running demo portfolio creation pipeline"
cd "../portfolio_creation_pipeline/"
python3 generate_returns.py

echo "running mv0 user_balance table updater"
cd "../mv0_user_balance_table_updater/"
python3 mv0_user_balance_table_updater.py

exec "$@"
