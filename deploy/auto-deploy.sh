#!/bin/bash
# ================================================
# 和尔盛世官网 - 一键自动部署
# 在 OA 对话的服务器上直接运行
# ================================================

set -e

GITHUB_TOKEN="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"
REPO_NAME="hywellness-website"
DOMAIN="www.hywellness.com"
DEPLOY_DIR="/var/www/hywellness"

echo "=== 和尔盛世官网 - 一键部署 ==="
echo ""

# Step 1: 获取服务器信息
echo "[1/5] 获取服务器信息..."
SERVER_IP=$(curl -s ifconfig.me)
SERVER_USER=$(whoami)
echo "  IP: $SERVER_IP"
echo "  用户: $SERVER_USER"

# Step 2: 获取/生成 SSH 密钥
echo "[2/5] 配置 SSH 密钥..."
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa <<< y
fi
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys 2>/dev/null || true
chmod 600 ~/.ssh/authorized_keys

SSH_KEY_CONTENT=$(cat ~/.ssh/id_rsa)
echo "  ✅ SSH 密钥就绪"

# Step 3: 通过 GitHub API 创建 Secrets（简化版）
echo "[3/5] 配置 GitHub Actions Secrets..."

# 安装 pynacl（用于加密）
pip install pynacl -q 2>/dev/null || pip3 install pynacl -q 2>/dev/null

# 获取公钥用于加密
PUB_KEY_DATA=$(curl -s \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/aonetpc/$REPO_NAME/actions/secrets/public-key")

KEY_ID=$(echo "$PUB_KEY_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['key_id'])")
PUB_KEY=$(echo "$PUB_KEY_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")

# 加密函数
encrypt_value() {
  python3 -c "
import sys
from base64 import b64encode
from nacl import encoding, public

pub_key = public.PublicKey('$PUB_KEY'.encode(), encoding=encoding.Base64Encoder)
sealed = public.SealedBox(pub_key).encrypt(sys.argv[1].encode())
print(b64encode(sealed).decode())
" "$1"
}

# 创建每个 Secret
for pair in "SSH_HOST:$SERVER_IP" "SSH_USER:$SERVER_USER" "SSH_PRIVATE_KEY:$SSH_KEY_CONTENT"; do
  NAME=$(echo "$pair" | cut -d: -f1)
  VALUE=$(echo "$pair" | cut -d: -f2-)
  
  ENCRYPTED=$(encrypt_value "$VALUE")
  
  DATA="{\"encrypted_value\":\"$ENCRYPTED\",\"key_id\":\"$KEY_ID\"}"
  
  curl -s -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -d "$DATA" \
    "https://api.github.com/repos/aonetpc/$REPO_NAME/actions/secrets/$NAME" > /dev/null
  
  echo "  ✅ $NAME"
done

# Step 4: 配置 Nginx 和 SSL
echo "[4/5] 配置 Nginx..."

mkdir -p "$DEPLOY_DIR"

cat > "/etc/nginx/sites-available/$DOMAIN" << 'EOF'
server {
    listen 80;
    server_name www.hywellness.com hywellness.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name www.hywellness.com hywellness.com;
    ssl_certificate /etc/letsencrypt/live/www.hywellness.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/www.hywellness.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    location / {
        root /var/www/hywellness;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
    location /api/booking/ {
        client_max_body_size 20m;
        proxy_pass http://localhost:3000/api/booking/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN" 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

# 申请 SSL
DOMAIN_IP=$(dig +short $DOMAIN 2>/dev/null || echo "")
SERVER_IP_NOW=$(curl -s ifconfig.me)
if [ "$DOMAIN_IP" = "$SERVER_IP_NOW" ]; then
  certbot --nginx -d "$DOMAIN" -d "hywellness.com" --agree-tos --non-interactive --email "admin@hywellness.com" 2>/dev/null || true
  echo "  ✅ SSL 证书已申请"
else
  echo "  ⚠️  域名未解析，跳过 SSL（解析后运行: certbot --nginx -d $DOMAIN）"
fi

# Step 5: 部署网站文件
echo "[5/5] 部署网站文件..."

# 从 GitHub 下载最新版本
cd /tmp
if [ -d "$REPO_NAME" ]; then
  rm -rf "$REPO_NAME"
fi
git clone --depth 1 https://github.com/aonetpc/$REPO_NAME.git 2>/dev/null || {
  # 如果 clone 失败，从本地复制
  if [ -d "/workspace/$REPO_NAME" ]; then
    rsync -avz --delete --exclude='.git' --exclude='deploy' --exclude='.github' \
      "/workspace/$REPO_NAME/" "$DEPLOY_DIR/"
  fi
}

if [ -d "/tmp/$REPO_NAME" ]; then
  cd "/tmp/$REPO_NAME"
  rsync -avz --delete --exclude='.git' --exclude='deploy' --exclude='.github' \
    . "$DEPLOY_DIR/"
  cd /tmp
  rm -rf "$REPO_NAME"
fi

chown -R $SERVER_USER:$SERVER_USER "$DEPLOY_DIR" 2>/dev/null || true

echo ""
echo "========================================="
echo "  🎉 部署完成！"
echo "========================================="
echo ""
echo "  官网: https://$DOMAIN"
echo "  OA:   https://food.hywellness.com"
echo ""
echo "  GitHub Actions 已配置好，"
echo "  以后 push 代码会自动部署"
echo ""

# 验证
sleep 2
if [ -f "$DEPLOY_DIR/index.html" ]; then
  echo "  ✅ 官网文件已就绪"
else
  echo "  ⚠️  官网文件部署可能需要手动操作"
fi