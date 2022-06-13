# Simple CircleCI Runner AutoScaling in AWS

## Purpose

This is a simple solution to scaling the number of [Circle Ci Runners](https://circleci.com/docs/2.0/runner-overview/) based on the number of jobs in the queue for that runner class.  It takes only minutes to set up.

## Notes about this configuration

Note the short timeout time for the CircleCI Runner and the shut down command in the associated service. Unclaimed runners should be terminated quickly, and runners that have completed should also.

Once started, instances will be largely in charge of their own lifecycle.  The Runner program will quit after a short idle time, and as the Runner is in single-task mode the service will also quit on completion (success or fail).  The runner service is configured to shut down the instance when it exits. 

Scale-in protection will be enabled in the Auto Scaling group to prevent instances in use from being terminated by the Auto Scaling group.

This prevents the scenario where multiple jobs are running in different instances, completing out of the order they were submitted, reducing the queue depth, and having the Auto Scaling group subsequently terminate the oldest instance to match the new smaller queue - even if a job is still running on it.

## Step 1: Preparing the Runner installation script

To use CircleCI runners, you will need to set up a Runner class.  An API token will be provided which will connect your Runners to CircleCI.

This can be done by following the steps at https://circleci.com/docs/2.0/runner-installation/index.html

Once completed, update the AUTH_TOKEN and RUNNER_NAME variables in the script `install_runner_ubuntu.sh`.

You will also need to add the steps to set up your runner environment - eg. if you are developing and testing a Node.js app, you will want to install Node.js.

The script will be executed at boot for each instance that is created in the scaling group.  It must be able to be run unattended (without user input).

# Step 2: Create launch template

Log in to AWS and navigate to the services page for managing EC2.

Go to `Launch Templates` and click `Create launch template`

Name your new template something sensible like `cci-runner-template`

Check the checkbox `Provide guidance to help me set up a template that I can use with EC2 Auto Scaling`

For the `Launch template contents` AMI, select Quick Start then `Ubuntu 22.04 LTS`

Select an `Instance type` - I'm using `t1.micro` as they are lightweight for testing purposes - you will need to pick one based on your requirements.

Select a `Key pair` for logging in, - you may wish to log in via SSH to troubleshoot an instance.

Under `Network settings` and `Security Groups`, select an existing security group or create one - it's recommended to allow only SSH from a trusted IP address, and blocking all other incoming traffic.  The CircleCI Runner polls the server for new jobs, and does not require any incoming connections.

Under `Advanced network configuration` click `Add network interface` and enable `Auto-assign public IP` for that interface

`Configure storage` - Increase the size of the hard disk for each instance if you think you'll need it.

Under `Advanced details'` copy and paste the contents of `install_runner_ubuntu.sh` in its entirety into `User data`.

This script will be executed once the instance has gone live, setting everything up.  Otherwise, you'd just have an base Ubuntu 22.04 instance with nothing installed.

Leave everything else as it is and click `Create Launch Template`.

You will see a success message. Scroll down and click `Create Auto Scaling group` below the `Create an Auto Scaling group from your template` heading.

***Be aware that the runner token api key details are stored in the launch template (as part of the runner install script), so don't share it!***

## Create Auto Scaling Group

If you did not follow the `Create an Auto Scaling group from your template` link above, go to the EC2 web console, navigate to 'Auto Scaling Groups' and click 'Create Auto Scaling group'

### Step 1: Choose launch template or configuration

Name your group something sensible like `name cci-runner-auto-scaling-group`.

Ensure the template created above is set as the `Launch template`.

Leave everything else as it is.

### Step 2: Choose instance launch options

Under `Instance launch options` select an `availability zone` and `subnet` - if your instances will need to communicate with other AWS assets, assign to the appropriate zone/subnet.

Leave everything else as it is.

### Step 3: Configure advanced options

Leave everything as it is.

### Step 4: Configure group size and scaling policies

Set `Desired capacity`, `Minimum capacity`, and `Maximum capacity` to `0` - our Lambda function will update these values to match our scaling requirements later.

Check `Enable scale-in protection` - This will protect instances in use from being terminated prematurely as the number of queued tasks decreases as discussed above.

Leave everything else as it is.

**You can skip steps 5/6**

### Step 7: Review
Review your configuration and save it click `Create Auto Scaling group`.

## Create IAM policy & role

Go to the IAM console and navigate to `Policies`.

Click `Create policy` and go to the `JSON editor`, copy and paste the contents of `lambda_iam.json` into that file.  This policy will give permissions to update auto scaling groups and read secrets from the AWS secrets manager - the two permissions the Lambda function which will do the scaling requires.

You can skip through assigning any tags.

Name the new something sensible like `cci-runner-lambda-iam-policy`.

Click `Create Policy`.

Navigate to the `Roles` section of IAM and click `Create role`.

Select `AWS service` as the `Trusted entity type` and select  `Lambda` as the `Use case`, then click `Next`.

Search the policies list for the policy we created earlier, and assign it to the role.

Name your role something sensible like `cci-runner-lambda-iam-role` and finish by clicking `Create role`.

## Create secrets

You will require the following secrets to be configured in [AWS secrets manager](https://aws.amazon.com/secrets-manager/) which provides a more secure way to store API keys and other sensitive information.

Go to the AWS secrets manager. Click `Store a new secret`.

### Step 1: Choose secret type

Select `Other type of secret`.

Add the following key value pairs:

`resource_class` - The resource class for the Runner in CCI in the format username/class-name
`circle_token` - This will be a CircleCI [personal token](https://circleci.com/docs/2.0/managing-api-tokens/) for polling the Runner API - it s not the runner token used in the installation script above.

For Encryption key leave it as `aws/secretsmanager`.

### Step 2: Configure secret

Name your secret something sensible like `cci-runner-lambda-secrets`.

Leave the rest as is.

### Step 3: Configure rotation - optional

Leave as-is.

### Step 4 Review:

Review and save.

*There's no need to copy and paste the generated code - it's already included in the included Lambda function, but take note of the secret name and region.*

Click `Store` to finish

## Create the Lambda function

Go to AWS Lambda

Click `Create function`.

Click `Author from scratch`.

Name your function something sensible like `cci-runner-lambda-function`.

Select the `Runtime` as `Python 3.8`.

Select the `Architechture` as `x64_64`.

Click `Execution role` and then `Use an existing role` and select the IAM role created above.

Click `Create function`.

Copy and paste the included function in `lambda-function.py` into the code source.

Under `Configuration` and then `Environmental variables`, edit and add the following key/value pairs:

    SECRET_NAME - The name of teh secret created above
    SECRET_REGION - The region of the secret above
    AUTO_SCALING_MAX - Integer value of the max number of instances to spin up
    AUTO_SCALING_GROUP_NAME - Name of the auto scaling group
    AUTO_SCALING_GROUP_REGION - The region of the auto scaling group

Leave everything else at the default.

## Trigger lambda on a schedule

Back at the Lambda function editing screen, click `Add trigger`.

Search for and select `EventBridge (CloudWatch Events)`.

Select `Create a new rule`.

Name your rule something sensible like `cci-runner-scheduled-trigger`.

Select `Rule type` as `Schedule expression`.

Enter the value `cron(0/1 * * * ? *)` which will trigger the function every minute.

Click `Add` to finish setting up the scheduled trigger.

## Testing and Deploying

Back to Lambda, to the `Code` tab, click `Deploy`.

To test, go to the `Test` tab

Leave everything as-is (to prevent the test being saved), and simply click `Test`.

You will see success or failure, and be able to debug if necessary.  If everything comes back green, you're up and running!

## Monitoring

You can use the `Monitor` tab in Lambda to ensure your function is running to the schedule you have set.

## Using the Runner

To use this runner to run CircleCI jobs, you must add it to your [CircleCI configuration](https://circleci.com/docs/2.0/configuration-reference/#self-hosted-runner).

You can see the `.circleci/config.yml` file in this repository for an example of this.