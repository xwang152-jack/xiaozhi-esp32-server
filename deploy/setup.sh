#!/bin/bash
# xiaozhi-esp32-server fork 版本一键部署脚本
# 用法: bash setup.sh
# 要求: Ubuntu/Debian, root 权限

set -e

INSTALL_DIR="/opt/xiaozhi-server"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_IP=$(hostname -I | awk '{print $1}')

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- 检查 root ---
if [ "$EUID" -ne 0 ]; then
    error "请使用 root 权限运行: sudo bash setup.sh"
fi

# --- 安装 Docker ---
install_docker() {
    if command -v docker &> /dev/null; then
        info "Docker 已安装: $(docker --version)"
        return
    fi

    info "安装 Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg

    DISTRO=$(lsb_release -cs)
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $DISTRO stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl start docker
    systemctl enable docker
    info "Docker 安装完成"
}

# --- 配置 Docker 镜像加速 ---
configure_docker_mirror() {
    if [ -f /etc/docker/daemon.json ] && grep -q "registry-mirrors" /etc/docker/daemon.json; then
        info "Docker 镜像加速已配置，跳过"
        return
    fi

    info "配置 Docker 镜像加速..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
    "dns": ["8.8.8.8", "114.114.114.114"],
    "registry-mirrors": ["https://docker.xuanyuan.me"]
}
EOF
    systemctl restart docker
    info "Docker 镜像加速配置完成"
}

# --- 创建目录 ---
create_dirs() {
    info "创建目录结构..."
    mkdir -p "$INSTALL_DIR"/{data,models/SenseVoiceSmall,uploadfile,mysql/data}
}

# --- 下载模型 ---
download_model() {
    local model_path="$INSTALL_DIR/models/SenseVoiceSmall/model.pt"
    if [ -f "$model_path" ]; then
        info "语音识别模型已存在，跳过下载"
        return
    fi

    info "下载 SenseVoice 语音识别模型（约 900MB）..."
    curl -fSL --progress-bar \
        https://modelscope.cn/models/iic/SenseVoiceSmall/resolve/master/model.pt \
        -o "$model_path" || error "模型下载失败"
    info "模型下载完成"
}

# --- 复制 docker-compose ---
deploy_compose() {
    cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    info "docker-compose.yml 已复制到 $INSTALL_DIR"
}

# --- 创建初始配置 ---
create_config() {
    local config_path="$INSTALL_DIR/data/.config.yaml"
    if [ -f "$config_path" ]; then
        warn ".config.yaml 已存在，跳过创建"
        return
    fi

    cat > "$config_path" <<EOF
server:
  ip: 0.0.0.0
  port: 8000
  http_port: 8003
  vision_explain: http://$PUBLIC_IP:8003/mcp/vision/explain
manager-api:
  url: http://xiaozhi-esp32-server-web:8002/xiaozhi
  secret: 待填写
EOF
    info "初始配置文件已创建: $config_path"
}

# --- 启动服务 ---
start_services() {
    info "拉取 Docker 镜像并启动服务（首次可能需要几分钟）..."
    cd "$INSTALL_DIR"
    docker compose up -d

    info "等待服务启动..."
    local timeout=300
    local start=$(date +%s)
    while true; do
        if docker logs xiaozhi-esp32-server-web 2>&1 | grep -q "Started AdminApplication"; then
            break
        fi
        local now=$(date +%s)
        if [ $((now - start)) -gt $timeout ]; then
            error "服务启动超时，请检查: docker compose logs"
        fi
        sleep 2
    done
    info "所有服务启动成功！"
}

# --- 打印结果 ---
print_result() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}  部署完成！${NC}"
    echo "=========================================="
    echo ""
    echo "服务地址:"
    echo "  智控台 (管理后台):  http://$PUBLIC_IP:8002"
    echo "  WebSocket (设备):   ws://$PUBLIC_IP:8000/xiaozhi/v1/"
    echo "  OTA 接口:           http://$PUBLIC_IP:8003/xiaozhi/ota/"
    echo "  视觉分析接口:       http://$PUBLIC_IP:8003/mcp/vision/explain"
    echo ""
    echo "接下来请完成以下配置:"
    echo ""
    echo "1. 云服务器安全组开放端口: 8000, 8002, 8003"
    echo ""
    echo "2. 浏览器打开智控台，注册第一个账号（= 超级管理员）"
    echo ""
    echo "3. 登录后进入「参数字典」→「参数管理」，找到 server.secret"
    echo "   复制该值，然后编辑配置文件:"
    echo "   vi $INSTALL_DIR/data/.config.yaml"
    echo "   将 secret: 待填写 替换为复制的值"
    echo ""
    echo "4. 重启 server 容器使配置生效:"
    echo "   docker restart xiaozhi-esp32-server"
    echo ""
    echo "5. 在智控台配置智能体（选择 LLM、ASR、TTS 提供商和 API Key）"
    echo ""
    echo "日常更新: cd $INSTALL_DIR && bash update.sh"
    echo "=========================================="
}

# --- 主流程 ---
main() {
    info "开始部署 xiaozhi-esp32-server (fork 版本)"
    install_docker
    configure_docker_mirror
    create_dirs
    download_model
    deploy_compose
    create_config
    start_services
    print_result
}

main
