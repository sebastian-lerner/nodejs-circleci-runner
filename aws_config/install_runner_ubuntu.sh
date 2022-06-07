#!/bin/bash

#-------------------------------------------------------------------------------
# CircleCI Runner installation script
# Based on the documentation at https://circleci.com/docs/2.0/runner-installation/
#-------------------------------------------------------------------------------

# Prerequisites:
# Complete these:
# https://circleci.com/docs/2.0/runner-installation/#authentication
# This script must be run as root
# This script was tested on Ubuntu 22.04

platform="linux/amd64"                                  # Runner platform: linux/amd64 || linux/arm64 || platform=darwin/amd64 
prefix="/opt/circleci"                                  # Runner install directory    

CONFIG_PATH="/opt/circleci/launch-agent-config.yaml"    # Determines where Runner config will be stored
SERVICE_PATH="/opt/circleci/circleci.service"           # Determines where the Runner service definition will be stored
TIMESTAMP=$(date +"%g%m%d-%H%M%S-%3N")                  # Used to avoid Runner naming collisions

AUTH_TOKEN=""                                           # Auth token for CircleCI
RUNNER_NAME=""                                          # A runner name - this is not the same as the Resource class - keep it short, and only with letters/numbers/dashes/underscores
UNIQUE_RUNNER_NAME="$RUNNER_NAME-$TIMESTAMP"            # Runners must have a unique name, so we'll append a timestamp
USERNAME="circleci"                                     # The user which the runner will execute as

#-------------------------------------------------------------------------------
# Update; install dependencies
#-------------------------------------------------------------------------------

apt update
apt install coreutils curl tar gzip -y

#-------------------------------------------------------------------------------
# Download, install, and verify the binary
#-------------------------------------------------------------------------------

mkdir -p "$prefix/workdir"
base_url="https://circleci-binary-releases.s3.amazonaws.com/circleci-launch-agent"
echo "Determining latest version of CircleCI Launch Agent"
agent_version=$(curl "$base_url/release.txt")
echo "Using CircleCI Launch Agent version $agent_version"
echo "Downloading and verifying CircleCI Launch Agent Binary"
curl -sSL "$base_url/$agent_version/checksums.txt" -o checksums.txt
file="$(grep -F "$platform" checksums.txt | cut -d ' ' -f 2 | sed 's/^.//')"
mkdir -p "$platform"
echo "Downloading CircleCI Launch Agent: $file"
curl --compressed -L "$base_url/$agent_version/$file" -o "$file"
echo "Verifying CircleCI Launch Agent download"
grep "$file" checksums.txt | sha256sum --check && chmod +x "$file"; cp "$file" "$prefix/circleci-launch-agent" || echo "Invalid checksum for CircleCI Launch Agent, please try download again"

#-------------------------------------------------------------------------------
# Install the CircleCI runner configuration
# CircleCI Runner will be executing as the configured $USERNAME
# Note the short idle timeout - this script is designed for auto-scaling scenarios - if a runner is unclaimed, it will quit and the system will shut down as defined in the below service definition
#-------------------------------------------------------------------------------

cat << EOF >$CONFIG_PATH
api:
  auth_token: $AUTH_TOKEN
runner:
  name: $UNIQUE_RUNNER_NAME
  command_prefix: ["sudo", "-niHu", "$USERNAME", "--"]
  working_directory: /opt/circleci/workdir/%s
  cleanup_working_directory: true
  idle_timeout: 1m
  max_run_time: 5h
  mode: single-task
EOF

# Set correct config file permissions and ownership
chown root: /opt/circleci/launch-agent-config.yaml
chmod 600 /opt/circleci/launch-agent-config.yaml

#-------------------------------------------------------------------------------
# Create the circleci user & give permissions to working directory 
# This user should NOT already exist
#-------------------------------------------------------------------------------

adduser --disabled-password --gecos GECOS "$USERNAME"
chown -R "$USERNAME" "$prefix/workdir"

#-------------------------------------------------------------------------------
# Create the service
# The service will shut down the system when it exits - that is, the runner has completed with a success or error
# If something goes wrong with the job, it's really not an issue if it quits and a new instance is launched for the next job - it may even be preferred
#-------------------------------------------------------------------------------

cat << EOF >$SERVICE_PATH
[Unit]
Description=CircleCI Runner
After=network.target
[Service]
ExecStart=$prefix/circleci-launch-agent --config $CONFIG_PATH
ExecStopPost=shutdown now -h
Restart=no
User=root
NotifyAccess=exec
TimeoutStopSec=18300
[Install]
WantedBy = multi-user.target
EOF

#-------------------------------------------------------------------------------
# Configure your runner environment
# This script must be able to run unattended - without user input
#-------------------------------------------------------------------------------
apt install -y nodejs npm

#-------------------------------------------------------------------------------
# Enable CircleCI Runner service and start it
# This MUST be done last, as it will immediately advertise to the CircleCI server that the runner is ready to use
#-------------------------------------------------------------------------------
systemctl enable $prefix/circleci.service
systemctl start circleci.service