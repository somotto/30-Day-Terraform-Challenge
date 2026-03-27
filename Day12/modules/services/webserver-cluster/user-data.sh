#!/bin/bash
set -e

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
  <head><title>${cluster_name} [${environment}] ${app_version}</title></head>
  <body>
    <h1>Hello World ${app_version}</h1>
    <p>Cluster: ${cluster_name}</p>
    <p>Environment: ${environment}</p>
    <p>Instance ID: $INSTANCE_ID</p>
    <p>Availability Zone: $AZ</p>
  </body>
</html>
HTML

cd /var/www/html
nohup python3 -m http.server ${server_port} &
