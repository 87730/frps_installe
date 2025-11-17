#!/bin/bash
# ------------------------------------------------------------
#  与原脚本 100% 兼容的“最小改动修正版”
#  修复点：
#  ① 允许 sudo 运行
#  ② 修正 arm 架构命名
#  ③ 配置示例文件备份 + 随机 token
#  ④ 安装完成提示放行 7000 端口
# ------------------------------------------------------------

# 1. 权限检查：root 或 sudo
if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        echo "🔔 非 root 用户，将尝试 sudo ..."
        exec sudo bash "$0" "$@"
    else
        echo "❌ 该脚本需要 root 权限，且系统未安装 sudo。"
        exit 1
    fi
fi

# 2. 颜色定义（保持不变）
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# 3. 安装依赖（保持不变）
install_dependencies() {
    if [ -x "$(command -v apt-get)" ]; then
        echo "🔧 安装依赖 (apt-get)..."
        apt-get update
        apt-get install -y wget tar curl
    elif [ -x "$(command -v yum)" ]; then
        echo "🔧 安装依赖 (yum)..."
        yum install -y wget tar curl
    elif [ -x "$(command -v dnf)" ]; then
        echo "🔧 安装依赖 (dnf)..."
        dnf install -y wget tar curl
    elif [ -x "$(command -v zypper)" ]; then
        echo "🔧 安装依赖 (zypper)..."
        zypper install -y wget tar curl
    elif [ -x "$(command -v pacman)" ]; then
        echo "🔧 安装依赖 (pacman)..."
        pacman -Sy --noconfirm wget tar curl
    else
        echo "⚠️ 无法识别的包管理器，尝试继续执行..."
    fi
}

# 4. 获取最新版本号（保持不变）
get_latest_version() {
    curl -sL https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# 5. 修正架构检测（与 GitHub 包名一致）
get_arch() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "arm"   ;;   # ← 修正
        armv6l)  echo "arm"   ;;   # ← 修正
        i386)    echo "386"   ;;
        i686)    echo "386"   ;;
        *)       echo "unsupported" ;;
    esac
}

# 6. detect_os 保持不变
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release; echo "$ID"
    elif type lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# 7. create_systemd_service 保持不变
create_systemd_service() {
    SERVICE_FILE="/etc/systemd/system/frps.service"
    INSTALL_DIR=$(pwd)

    if [ -f "$SERVICE_FILE" ]; then
        echo "⚠️ 检测到已存在的服务文件: $SERVICE_FILE"
        read -p "是否覆盖？(y/N) " OVERWRITE
        [[ ! "$OVERWRITE" =~ ^[yY] ]] && echo "跳过 systemd 服务创建。" && return
    fi

    echo "🛠️ 创建 systemd 服务..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=frp server
After=network.target syslog.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/frps -c $INSTALL_DIR/frps.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frps >/dev/null 2>&1
    echo "✅ systemd 服务创建完成！"
    echo "服务文件位置: $SERVICE_FILE"

    read -p "是否立即启动 frps 服务？(Y/n) " START_NOW
    if [[ ! "$START_NOW" =~ ^[nN] ]]; then
        systemctl start frps
        echo "🚀 frps 服务已启动！"
        show_service_status
    else
        echo "您可以使用以下命令手动启动服务:"
        echo "  systemctl start frps"
    fi
}

# 8. is_frps_installed / show_service_status 保持不变
is_frps_installed() {
    [ -f "/etc/systemd/system/frps.service" ] && return 0
    [ -f "$(pwd)/frps" ] && [ -f "$(pwd)/frps.toml" ] && return 0
    return 1
}

show_service_status() {
    if systemctl is-active frps >/dev/null 2>&1; then
        echo -e "🟢 FRPS 状态: ${GREEN}运行中${NC}"
    elif systemctl is-enabled frps >/dev/null 2>&1; then
        echo -e "🟡 FRPS 状态: ${YELLOW}已安装但未运行${NC}"
    else
        echo -e "🔴 FRPS 状态: ${RED}未安装或未配置${NC}"
    fi
}

# 9. show_management_menu 保持不变
show_management_menu() {
    clear
    echo -e "${BLUE}==============================${NC}"
    echo -e "${BLUE}      FRPS 服务管理菜单       ${NC}"
    echo -e "${BLUE}==============================${NC}"
    show_service_status; echo ""

    if systemctl is-active frps >/dev/null 2>&1; then
        echo -e "1. ${RED}启动服务${NC} (服务已运行)"
    else
        echo -e "1. ${GREEN}启动服务${NC}"
    fi
    echo -e "2. ${YELLOW}重启服务${NC}"
    echo -e "3. ${RED}停止服务${NC}"
    echo -e "4. ${RED}卸载 FRPS${NC}"
    echo -e "5. 退出"
    echo -e "${BLUE}==============================${NC}"
    echo -n "请选择操作 [1-5]: "
}

# 10. uninstall_frps 保持不变
uninstall_frps() {
    echo "⚠️ 开始卸载 FRPS..."
    if systemctl is-active frps >/dev/null 2>&1; then
        systemctl stop frps; echo "🛑 服务已停止"
    fi
    if systemctl is-enabled frps >/dev/null 2>&1; then
        systemctl disable frps; echo "🔌 服务已禁用"
    fi
    SERVICE_FILE="/etc/systemd/system/frps.service"
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"; echo "🗑️ 服务文件已删除"
        systemctl daemon-reload
    fi
    INSTALL_DIR=$(pwd)
    [ -f "$INSTALL_DIR/frps" ] && rm -f "$INSTALL_DIR/frps" && echo "🗑️ 服务端程序已删除"
    if [ -f "$INSTALL_DIR/frps.toml" ]; then
        read -p "是否删除配置文件 frps.toml？(y/N) " DELETE_CONFIG
        if [[ "$DELETE_CONF