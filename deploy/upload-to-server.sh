#!/bin/bash
# ================================================
# 酒店官网 - 接收部署文件脚本
# 在服务器上执行，将网站文件同步到部署目录
# 绝不会影响 OA 系统
# ================================================

set -e

DEPLOY_DIR="/var/www/hotelhuayi"

if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m请使用 sudo 运行此脚本\033[0m"
  exit 1
fi

if [ ! -f "./index.html" ]; then
  echo -e "\033[31m错误: 当前目录没有 index.html\033[0m"
  echo "请在网站根目录执行此脚本"
  exit 1
fi

echo "=== 部署酒店官网 ==="
echo "源目录: $(pwd)"
echo "目标: $DEPLOY_DIR"
echo ""

mkdir -p "$DEPLOY_DIR"

echo "同步文件（rsync --delete 仅在 $DEPLOY_DIR 内清理)...”
rsync -avz --delete \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='deploy' \
  --exclude='README*' \
  --exclude='*.sh' \
  ./ "$DEPLOY_DIR"/

chown -R ubuntu:ubuntu "$DEPLOY_DIR"

echo ""
echo "✅ 部署完成！"
echo "访问: https://www.hotelhuayi.com"

echo ""
echo "验证:"
sudo ls -la "$DEPLOY_DIR/index.html"
echo "检查Nginx:"
sudo nginx -t && echo "✅ Nginx 正常"