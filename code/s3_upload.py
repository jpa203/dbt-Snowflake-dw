import boto3 
import configparser
from utils import upload_table

# configurations 
parser = configparser.ConfigParser()
parser.read('pipeline.conf')
access_key = parser.get('aws_boto_credentials', 'access_key')
secret_key = parser.get('aws_boto_credentials', 'secret_key')
bucket_name = parser.get('aws_boto_credentials', 'bucket_name')

s3 = boto3.client('s3', aws_access_key_id=access_key, aws_secret_access_key=secret_key)

table_name = ['Country', 'League', 'Match', 'Player', 'Player_Attributes', 'Team', 'Team_Attributes']



for table in table_name:

    try: 

        csv = upload_table(table_name=table)

        s3.upload_file(csv, bucket_name, table)

        print(f'{table} uploaded to S3 Bucket')

    except Exception as e:
        print (f'Error: {e}')








