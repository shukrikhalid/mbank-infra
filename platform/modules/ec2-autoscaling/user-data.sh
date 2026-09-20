#!/bin/bash
# User data script for EC2 instances
# Installs SSM agent, CloudWatch agent, and runs custom initialization

set -ex

# Update system
yum update -y

# Install SSM Agent (usually pre-installed on Amazon Linux 2)
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Fetch CloudWatch Agent configuration from SSM Parameter Store and start
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c ssm:${cw_config_param}

# Run custom user data if provided
%{ if user_data_b64 != "" }
echo "${user_data_b64}" | base64 -d | bash
%{ endif }

echo "User data script completed successfully"
