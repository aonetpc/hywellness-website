#!/bin/bash
# ================================================
# 和尔盛世官网 - 服务器一键部署脚本
# 域名: www.hywellness.com
# 用途: 首次配置，创建独立站点，不影响现有OA系统
# ================================================

set -e

DOMAIN="www.hywellness.com"
EMAIL="admin@hywellness.com"
DEPLOY_DIR="/var/www/hywellness"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  和尔盛世官网 - 服务器部署脚本${NC}"
echo -e "${GREEN}  域名: $DOMAIN${NC}"
echo -e "${GREEN}  部署目录: $DEPLOY_DIR${NC}"
echo -e "${GREEN}  ⚠️ 不会影响现有OA系统${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 sudo 或 root 用户运行此脚本${NC}"
  exit 1
fi

echo -e "${YELLOW}[1/7] 创建部署目录（独立目录，不影响OA）...${NC}"
mkdir -p "$DEPLOY_DIR"
chown -R ubuntu:ubuntu "$DEPLOY_DIR"
echo -e "  ${GREEN}✅ $DEPLOY_DIR${NC}"

echo -e "${YELLOW}[2/7] 检查 Nginx 是否安装...${NC}"
if ! command -v nginx &> /dev/null; then
  apt-get update -qq
  apt-get install -y -qq nginx certbot python3-certbot-nginx
fi
echo -e "  ${GREEN}✅ Nginx 已就绪${NC}"

echo -e "${YELLOW}[3/7] 检查域名解析...${NC}"
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
DOMAIN_IP=$(dig +short $DOMAIN 2>/dev/null || nslookup $DOMAIN 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
echo "  服务器IP: $SERVER_IP"
echo "  域名解析: ${DOMAIN_IP:-未解析}"
if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
  echo -e "  ${RED}⚠️ 域名尚未解析到此服务器${NC}"
  echo "  请在DNS管理中添加A记录: $DOMAIN → $SERVER_IP"
  echo "  继续配置Nginx和SSL（证书申请可能会失败）"
fi

echo -e "${YELLOW}[4/7] 配置 Nginx（独立站点，不修改OA配置）...${NC}"

cat > "/etc/nginx/sites-available/$DOMAIN" << 'NGINXEOF'
server {
    listen 80;
    server_name www.hywellness.com hywellness.com;

    # 自动跳转到HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name www.hywellness.com hywellness.com;

    # SSL证书（稍后由certbot生成，此处留占位）
    ssl_certificate /etc/letsencrypt/live/www.hywellness.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/www.hywellness.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # 官网静态文件
    location / {
        root /var/www/hywellness;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    # === 预订API - 转发到OA后端（与OA系统共享）===
    # 官网的预订/咨询表单数据通过OA后端处理
    location /api/booking/ {
        client_max_body_size 20m;
        proxy_pass http://localhost:3000/api/booking/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 缓存优化
    location ~* \.(?:woff2?|ttf|eot|otf)$ {
        root /var/www/hywellness;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ~* \.(?:jpg|jpeg|png|gif|ico|svg|webp|avif)$ {
        root /var/www/hywellness;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ~* \.(?:css|js)$ {
        root /var/www/hywellness;
        expires 7d;
        add_header Cache-Control "public";
    }
}
NGINXEOF

ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"

echo -e "  ${GREEN}✅ Nginx 站点配置已创建${NC}"

echo -e "${YELLOW}[5/7] 测试 Nginx 配置（确保不影响OA）...${NC}"
nginx -t
echo -e "  ${GREEN}✅ Nginx 配置正确${NC}"

echo -e "${YELLOW}[6/7] 重载 Nginx（优雅重载，OA不中断）...${NC}"
systemctl reload nginx
echo -e "  ${GREEN}✅ Nginx 已重载${NC}"

echo -e "${YELLOW}[7/7] 申请 SSL 证书...${NC}"
if [ "$SERVER_IP" = "$DOMAIN_IP" ]; then
  if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    certbot --nginx -d "$DOMAIN" -d "hywellness.com" --agree-tos --non-interactive --email "$EMAIL"
    echo -e "  ${GREEN}✅ SSL 证书已申请${NC}"
  else
    certbot renew --quiet
    echo -e "  ${GREEN}✅ SSL 证书已存在${NC}"
  fi
else
  echo -e "  ${YELLOW}⚠️ 域名未解析，跳过证书申请${NC}"
  echo -e "  解析完成后，运行: sudo certbot --nginx -d $DOMAIN -d hywellness.com"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ 配置完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  ${YELLOW}官网地址:${NC}   https://$DOMAIN"
echo -e "  ${YELLOW}OA系统:${NC}     https://food.hywellness.com"
echo -e "  ${YELLOW}部署目录:${NC}   $DEPLOY_DIR"
echo -e "  ${YELLOW}API共享:${NC}    /api/booking/ → OA后端(:3000)"
echo ""
echo -e "  ${YELLOW}与OA系统完全隔离:${NC}"
echo "  - OA:  food.hywellness.com → /var/www/food-purchase/ + /opt/food-purchase/backend/"
echo "  - 官网: www.hywellness.com → /var/www/hywellness/ (独立目录)"
echo "  - 共享: /api/booking/ 转发到同一 OA 后端"
echo ""
echo -e "  ${YELLOW}下一步:${NC}"
echo "  1. 将网站文件上传到 $DEPLOY_DIR"
echo "  2. 或配置 GitHub Actions 自动部署"
echo "  3. 测试: curl -I https://$DOMAIN"