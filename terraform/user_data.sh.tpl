#!/bin/bash
set -euxo pipefail

dnf install -y httpd

# IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>${project_name}</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <h1>${project_name}</h1>
  <p>Served by instance <strong>$IID</strong> in <strong>$AZ</strong></p>
</body>
</html>
HTML

# Health check endpoint used by the ALB target group and Route 53
echo "OK" > /var/www/html/health

systemctl enable --now httpd
