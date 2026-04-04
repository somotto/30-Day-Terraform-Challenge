#!/bin/bash
set -euo pipefail

# IMDSv2 token — required for metadata access on Amazon Linux 2023
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

SECRET_VALUE="(not configured)"

%{ if secret_source == "ssm" ~}
SECRET_VALUE=$(aws ssm get-parameter \
  --region "$REGION" \
  --name "${secret_ref}" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text 2>/dev/null || echo "(ssm fetch failed)")
%{ endif ~}

%{ if secret_source == "secretsmanager" ~}
SECRET_VALUE=$(aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "${secret_ref}" \
  --query "SecretString" \
  --output text 2>/dev/null || echo "(secretsmanager fetch failed)")
%{ endif ~}

mkdir -p /var/www/html

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
  <head><meta charset="UTF-8"><title>${cluster_name} [${environment}] ${app_version}</title></head>
  <body>
    <h1>Hello World — ${app_version}</h1>
    <p>Cluster: ${cluster_name}</p>
    <p>Environment: ${environment}</p>
    <p>Instance ID: $INSTANCE_ID</p>
    <p>Availability Zone: $AZ</p>
    <p>Secret source: ${secret_source}</p>
  </body>
</html>
HTML

cd /var/www/html
nohup python3 -m http.server ${server_port} &
