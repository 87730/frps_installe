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
        if [[ "$DELETE_CONFIG" =~ ^[yY] ]]; then
            rm -f "$INSTALL_DIR/frps.toml"; echo "🗑️ 配置文件已删除"
        else
            echo "🔒 保留配置文件: $INSTALL_DIR/frps.toml"
        fi
    fi
    echo -e "\n✅ FRPS 卸载完成！"
}

# 11. handle_download_failure 保持不变
handle_download_failure() {
    echo -e "\n❌ ${RED}下载失败！${NC}"
    echo "请手动下载 FRP 文件:"
    echo "  URL: $URL"
    echo "保存到当前目录后重新运行脚本"
    read -p "按任意键退出脚本..." -n1 -s
    exit 1
}

# 12. 主安装函数（关键改动：备份示例配置 + 随机 token + 端口提示）
install_frps() {
    OS=$(detect_os); echo "💻 检测到系统: $OS"
    install_dependencies

    VERSION=$(get_latest_version)
    ARCH=$(get_arch)
    [ "$ARCH" = "unsupported" ] && echo "❌ 不支持的架构: $(uname -m)" && exit 1

    FILENAME="frp_${VERSION}_linux_${ARCH}.tar.gz"
    URL="https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILENAME}"

    echo "🔍 系统架构: ${ARCH}"
    echo "🆕 最新版本: v${VERSION}"
    echo "⏬ 下载 FRP..."

    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$URL" || handle_download_failure
    elif command -v curl >/dev/null 2>&1; then
        curl -LO --progress-bar "$URL" || handle_download_failure
    else
        echo "❌ 未找到 wget 或 curl"; exit 1
    fi

    [ ! -f "$FILENAME" ] && handle_download_failure
    echo "📦 解压文件..."
    tar xzf "$FILENAME"

    EXTRACTED_DIR="frp_${VERSION}_linux_${ARCH}"
    [ ! -d "$EXTRACTED_DIR" ] && EXTRACTED_DIR="frp_${VERSION}"
    [ ! -d "$EXTRACTED_DIR" ] && echo "❌ 解压目录未找到: $EXTRACTED_DIR" && exit 1

    cd "$EXTRACTED_DIR" || exit
    echo "🧹 清理文件..."
    mv frps frps.toml ../
    cd ..

    # ------------ 新增：备份示例 + 随机 token ------------
    if [ ! -f frps.toml ]; then
        cp frps.toml.example frps.toml
        TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
        sed -i "s/^token.*/token = \"$TOKEN\"/" frps.toml
        echo -e "${YELLOW}⚙️  已生成初始配置文件 frps.toml，token 已设为 ${TOKEN}${NC}"
    fi
    # -----------------------------------------------------

    rm -rf "$EXTRACTED_DIR" "$FILENAME"
    echo -e "\n✅ FRP 服务端安装成功！"
    echo "======================================"
    echo "服务端文件: $(pwd)/frps"
    echo "配置文件:   $(pwd)/frps.toml"
    echo "======================================"

    # ------------ 新增：防火墙提示 ------------
    echo -e "${BLUE}🔒 若系统启用防火墙，请放行端口 7000/tcp 及后续穿透端口${NC}"
    echo -e "   Ubuntu/Debian   : sudo ufw allow 7000/tcp"
    echo -e "   CentOS/RHEL 7/8 : sudo firewall-cmd --permanent --add-port=7000/tcp && sudo firewall-cmd --reload"
    # -----------------------------------------------------

    read -p "是否配置 systemd 服务以开机自启？(Y/n) " SETUP_SERVICE
    if [[ ! "$SETUP_SERVICE" =~ ^[nN] ]]; then
        create_systemd_service
    else
        echo -e "\n您可以使用以下命令手动启动:"
        echo "  $(pwd)/frps -c $(pwd)/frps.toml"
    fi
}

# 13. main 保持不变
main() {
    if is_frps_installed; then
        while true; do
            show_management_menu; read choice
            case $choice in
                1) if systemctl is-active frps >/dev/null 2>&1; then
                       echo -e "${RED}❌ 服务已在运行中，无需启动${NC}"
                   else
                       systemctl start frps; echo -e "${GREEN}✅ 服务已启动${NC}"
                   fi; sleep 2 ;;
                2) systemctl restart frps; echo -e "${YELLOW}🔄 服务已重启${NC}"; sleep 2 ;;
                3) if systemctl is-active frps >/dev/null 2>&1; then
                       systemctl stop frps; echo -e "${RED}🛑 服务已停止${NC}"
                   else
                       echo -e "${YELLOW}⚠️ 服务未运行，无需停止${NC}"
                   fi; sleep 2 ;;
                4) read -p "⚠️ 确定要卸载 FRPS 吗？(y/N) " CONFIRM_UNINSTALL
                   if [[ "$CONFIRM_UNINSTALL" =~ ^[yY] ]]; then
                       uninstall_frps; exit 0
                   else
                       echo "卸载已取消"
                   fi; sleep 2 ;;
                5) echo "退出管理菜单"; exit 0 ;;
                *) echo -e "${RED}无效选择，请重新输入${NC}"; sleep 1 ;;
            esac
        done
    else
        install_frps
    fi
}

# 14. 执行
main
get_latest_ver() {
    curl -sL https://api.github.com/repos/fatedier/frp/releases/latest | \
    grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# 5. 修正后的架构检测（对应 frp 官方包名）
get_arch() {
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "arm"   ;;
        armv6l)  echo "arm"   ;;   # frp 未区分 v6/v7，统一用 arm
        i386|i686) echo "386" ;;
        *) echo "unsupported"; exit 1 ;;
    esac
}

# 6. 安装目录（可自定义）
INSTALL_DIR="/opt/frps"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# 7. 主安装流程
install_frps() {
    install_deps
    VERSION=$(get_latest_ver)
    ARCH=$(get_arch)
    FILE="frp_${VERSION}_linux_${ARCH}.tar.gz"
    URL="https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILE}"

    echo -e "${GREEN}⏬ 下载 frp v${VERSION} ${ARCH}...${NC}"
    wget -q --show-progress "$URL" || { echo "❌ 下载失败"; exit 1; }

    echo "📦 解压..."
    tar xzf "$FILE"
    mv "frp_${VERSION}_linux_${ARCH}/frps" .
    mv "frp_${VERSION}_linux_${ARCH}/frps.toml" frps.toml.example
    rm -rf "$FILE" "frp_${VERSION}_linux_${ARCH}"

    # 8. 初始化配置文件
    if [[ ! -f frps.toml ]]; then
        cp frps.toml.example frps.toml
        # 安全默认值：随机 token
        TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
        sed -i "s/^token.*/token = \"$TOKEN\"/" frps.toml
        echo -e "${YELLOW}⚙️  已生成初始配置文件 frps.toml，token 为 ${TOKEN}${NC}"
    fi

    # 9. 创建 systemd 服务
    cat >/etc/systemd/system/frps.service <<EOF
[Unit]
Description=frp server
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/frps -c $INSTALL_DIR/frps.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable frps

    # 10. 防火墙提示
    echo -e "${BLUE}🔒 若系统启用防火墙，请放行端口 7000/tcp 及后续穿透端口${NC}"
    echo -e "   Ubuntu/Debian   : ufw allow 7000/tcp"
    echo -e "   CentOS/RHEL 7/8 : firewall-cmd --permanent --add-port=7000/tcp && firewall-cmd --reload"

    # 11. 启动并查看状态
    systemctl start frps
    systemctl status frps --no-pager
}

# 12. 入口
install_frps
