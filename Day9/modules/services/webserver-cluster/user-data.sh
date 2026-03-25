#!/bin/bash
set -e

# Fetch instance metadata using IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

mkdir -p /var/www/html

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
  <head><title>${cluster_name}</title></head>
  <body>
    <h1>Hello from ${cluster_name}</h1>
    <p>Instance ID: $INSTANCE_ID</p>
    <p>Availability Zone: $AZ</p>
    <p>Environment: ${environment}</p>
  </body>
</html>
HTML

cd /var/www/html
nohup python3 -m http.server ${server_port} &
