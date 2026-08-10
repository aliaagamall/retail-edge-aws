#!/bin/bash

set -e

APP_DIR="/home/ec2-user/app-tier"

dnf update -y

dnf install -y git nginx mysql

curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

cd /home/ec2-user

if [ ! -d "/home/ec2-user/aws-three-tier-web-architecture-workshop" ]; then
    git clone https://github.com/aws-samples/aws-three-tier-web-architecture-workshop.git
fi

rm -rf "$APP_DIR"

cp -r \
    /home/ec2-user/aws-three-tier-web-architecture-workshop/application-code/app-tier \
    "$APP_DIR"

chown -R ec2-user:ec2-user "$APP_DIR"

cd "$APP_DIR"

npm install

echo "Application files are ready."

echo "Configure DbConfig.js with the RDS credentials before starting the application."

cat > /etc/nginx/conf.d/retailedge-loadtest.conf <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

rm -f /etc/nginx/conf.d/default.conf

nginx -t

systemctl enable nginx
systemctl restart nginx

echo "Nginx configuration completed."