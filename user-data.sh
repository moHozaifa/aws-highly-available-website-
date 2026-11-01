#!/bin/bash
# EC2 user-data script for the Launch Template (Amazon Linux 2023)
# Replace YOUR-BUCKET-NAME with your S3 bucket name before using.

# Save all script output to a log file (helps with troubleshooting)
exec > >(tee /var/log/user-data.log) 2>&1

# 1. Install and start Nginx
dnf install -y nginx
systemctl enable --now nginx

# 2. Download the website page from S3 (uses the instance's IAM role, no keys needed)
aws s3 cp s3://YOUR-BUCKET-NAME/index.html /usr/share/nginx/html/index.html

# 3. Ask the instance metadata service (IMDSv2) for this server's ID and AZ
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

# 4. Write the instance details into the page
sed -i "s/INSTANCE_INFO/Served by: $ID ($AZ)/" /usr/share/nginx/html/index.html
