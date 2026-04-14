#!/bin/bash
set -euo pipefail

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
  <head>
    <meta charset="UTF-8">
    <title>${cluster_name} [${environment}] ${app_version}</title>
    <style>
      body { font-family: monospace; max-width: 640px; margin: 40px auto; padding: 0 20px; }
      h1   { color: #1a4a8a; }
      .badge { display: inline-block; background: #1a4a8a; color: #fff;
               padding: 2px 8px; border-radius: 4px; font-size: 0.85em; }
      .workflow { background: #f0f4ff; border-left: 4px solid #1a4a8a;
                  padding: 8px 12px; margin-top: 16px; font-size: 0.9em; }
      .tag { background: #e8f5e9; border-left: 4px solid #2e7d32;
             padding: 8px 12px; margin-top: 8px; font-size: 0.85em; }
    </style>
  </head>
  <body>
    <h1>Hello World — <span class="badge">${app_version}</span></h1>
    <p>Cluster: <strong>${cluster_name}</strong></p>
    <p>Environment: <strong>${environment}</strong></p>
    <p>Instance ID: $INSTANCE_ID</p>
    <p>Availability Zone: $AZ</p>
    <p>Secret source: ${secret_source}</p>
    <div class="workflow">
      Day 22 — Integrated pipeline: plan artifact promoted from dev to production.
      Sentinel policies enforced. Cost gate active.
    </div>
    <div class="tag">
      ManagedBy: terraform &nbsp;|&nbsp; Sentinel: compliant
    </div>
  </body>
</html>
HTML

cd /var/www/html
nohup python3 -m http.server ${server_port} &
