#!/bin/bash
# xiaozhi-esp32-server 更新脚本
# 用法: bash update.sh
# 前提: 本地代码已 push，GitHub Actions 构建已完成

set -e

INSTALL_DIR="/opt/xiaozhi-server"
cd "$INSTALL_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

info "拉取最新镜像..."
docker compose pull

info "重启服务（零停机更新）..."
docker compose up -d

info "等待服务就绪..."
sleep 5

echo ""
echo "当前运行状态:"
docker compose ps

echo ""
info "更新完成！查看日志:"
echo "  docker compose logs -f xiaozhi-esp32-server      # Python 核心服务"
echo "  docker compose logs -f xiaozhi-esp32-server-web   # 管理后台"
