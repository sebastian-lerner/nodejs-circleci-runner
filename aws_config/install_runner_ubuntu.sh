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

AUTH_TOKEN=""                                           # Auth token for CircleCI

#-------------------------------------------------------------------------------
# Update; install dependencies
#-------------------------------------------------------------------------------

apt update
apt install coreutils curl tar gzip -y

#-------------------------------------------------------------------------------
# Download, install, and verify the binary
#-------------------------------------------------------------------------------

echo "Installing CircleCI self-hosted runner"
curl -s https://packagecloud.io/install/repositories/circleci/runner/script.deb.sh?any=true | sudo bash

sudo apt install -y circleci-runner
echo "Verifying CircleCI machine runner has installed"
circleci-runner --version && echo "CircleCI machine runner has been installed" || echo "CircleCI Runner is not installed"
sudo sed -i "s/<< AUTH_TOKEN >>/$AUTH_TOKEN/g" /etc/circleci-runner/circleci-runner-config.yaml

echo "CircleCI Runner config -"
sed "s/$AUTH_TOKEN/here_is_the_hidden_auth/" /etc/circleci-runner/circleci-runner-config.yaml

#-------------------------------------------------------------------------------
# Configure your runner environment
# This script must be able to run unattended - without user input
#-------------------------------------------------------------------------------
apt install -y nodejs npm

#-------------------------------------------------------------------------------
# Enable CircleCI Runner service and start it
# This MUST be done last, as it will immediately advertise to the CircleCI server that the runner is ready to use
#-------------------------------------------------------------------------------
sudo systemctl enable circleci-runner
sudo systemctl start circleci-runner
# Check status
sudo systemctl status circleci-runner
