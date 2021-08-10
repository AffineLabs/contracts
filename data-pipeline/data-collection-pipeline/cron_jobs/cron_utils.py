import json
import logging
import os
import time

try:
    import boto3
    from botocore.exceptions import ClientError
    s3 = boto3.resource('s3')
    S3_ENABLED = True
except ImportError:
    logging.warning('Boto3 integration failed, S3 uploading/downloading is disabled.')
    S3_ENABLED = False

def get_timestamp():
    return str(time.time())
    
def write_to_file(dataframe, save_dir=None, file_name=None):
    filename_hash = get_timestamp()
    if file_name:
        filename_hash = file_name + '_' + filename_hash
    if not filename_hash.endswith('.csv'):
        filename_hash += '.csv'
    if save_dir:
        filename_hash = os.path.join(save_dir, filename_hash)

    with open(filename_hash, 'w') as f:
        dataframe.to_csv(filename_hash)
    return filename_hash
        
def upload_to_s3(bucket, file_path, filename):
    if S3_ENABLED:
        s3.Bucket(bucket).upload_file(file_path, filename)
        return True
    return False

def get_file_from_s3(bucket, filename, file_path):
    if S3_ENABLED:
        s3.Object(bucket, filename).download_file(file_path)
        return True
    return False

def get_most_recent_s3_object(bucket_name, file_prefix=None):
    # Taken from https://stackoverflow.com/a/62864288
    if S3_ENABLED:
        s3 = boto3.client('s3')
        paginator = s3.get_paginator( "list_objects_v2" )
        page_iterator = paginator.paginate(Bucket=bucket_name, Prefix=file_prefix)
        latest = None
        for page in page_iterator:
            if "Contents" in page:
                latest2 = max(page['Contents'], key=lambda x: x['LastModified'])
                if latest is None or latest2['LastModified'] > latest['LastModified']:
                    latest = latest2
        return latest

def download_most_recent_s3_file_in_bucket(downloaded_file_path, bucket_name, file_prefix=None):
    if S3_ENABLED:
        latest = get_most_recent_s3_object(bucket_name, file_prefix)
        obj_key = latest['Key']
        s3.Bucket(bucket_name).download_file(obj_key, downloaded_file_path)
        return True
    return False

def create_bucket(bucket_name, region=None):
    """Create an S3 bucket in a specified region

    If a region is not specified, the bucket is created in the S3 default
    region (us-east-1).

    :param bucket_name: Bucket to create
    :param region: String region to create bucket in, e.g., 'us-west-2'
    :return: True if bucket created, else False
    """

    # Create bucket
    try:
        if region is None:
            s3_client = boto3.client('s3')
            s3_client.create_bucket(Bucket=bucket_name)
        else:
            s3_client = boto3.client('s3', region_name=region)
            location = {'LocationConstraint': region}
            s3_client.create_bucket(Bucket=bucket_name,
                                    CreateBucketConfiguration=location)
    except ClientError as e:
        logging.error(e)
        return False
    return True