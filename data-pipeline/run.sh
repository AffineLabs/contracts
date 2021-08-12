#! /bin/sh

echo "running data collection pipeline"
python3 "./data-collection-pipeline/data_pipeline.py"

echo "running data preprocessing pipeline"
python3 "./data-preprocessing-pipeline/main.py"

exec "$@"