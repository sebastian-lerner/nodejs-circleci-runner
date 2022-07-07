import json, urllib3, boto3, base64, os

# This script polls the queue depth for a Circle CI runner class, and sets the parameters for an AWS Auto Scaling group 
# It uses the CircleCI runner API https://circleci.com/docs/2.0/runner-api/
# It requires the included IAM role and should be triggered every minute using an EventBridge Cron event

# Retrieve environment variables
secret_name   = os.environ['SECRET_NAME'] 
secret_region = os.environ['SECRET_REGION']
auto_scaling_max = os.environ['AUTO_SCALING_MAX'] 
auto_scaling_group_name = os.environ['AUTO_SCALING_GROUP_NAME']
auto_scaling_group_region = os.environ['AUTO_SCALING_GROUP_REGION']

# Function to retrieve secrets from AWS Secrets manager
# https://aws.amazon.com/secrets-manager/
def get_secret(secret_name, region_name):
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    get_secret_value_response = client.get_secret_value(
        SecretId=secret_name
    )
  
    if 'SecretString' in get_secret_value_response:
        secret = get_secret_value_response['SecretString']
        return(secret)
    else:
        decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
        return(decoded_binary_secret)

# Make a HTTP GET request with the given URL and headers
def get_request(url, headers):
    http = urllib3.PoolManager()
    r = http.request('GET', url, headers=headers)
    r_json = json.loads(r.data.decode("utf-8"))
    return(r_json)

# The handler function - is executed every time the Lambda function is triggered
def lambda_handler(event, context):
    # Get secrets
    secrets = json.loads(get_secret(secret_name, secret_region))
    
    # Configure Runner API endpoint https://circleci.com/docs/2.0/runner-api/#endpoints
    endpoint_url = 'https://runner.circleci.com/api/v2/tasks?resource-class=' + secrets['resource_class']
    headers = {'Circle-Token': secrets['circle_token']}

    # Get result from API endpoint
    result = get_request(endpoint_url, headers)

    # Update the auto scaling group with a desired number of instances set to the number of jobs in the queue, or the maximum, whichever is smallest
    instances_min = 0
    instances_max = int(auto_scaling_max)
    instances_desired = int(result["unclaimed_task_count"]) if int(result["unclaimed_task_count"]) < int(auto_scaling_max) else int(auto_scaling_max)
    
    # Set the Auto Scaling group configuration
    client = boto3.client('autoscaling', region_name=auto_scaling_group_region)
    client.update_auto_scaling_group(
        AutoScalingGroupName=auto_scaling_group_name,
        MinSize=instances_min,
        MaxSize=instances_max,
        DesiredCapacity=instances_desired
    )  

    # Lambda functions should return a result, even if it isn't used
    return result["unclaimed_task_count"]