#!/bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo "❌ 该脚本需要以 root 用户权限运行。"
    echo "请使用 'sudo -i' 切换到 root 用户后再运行此脚本"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 重置颜色

# 安装必要依赖
install_dependencies() {
    if [ -x "$(command -v apt-get)" ]; then
        # Debian/Ubuntu
        echo "🔧 安装依赖 (apt-get)..."
        apt-get update
        apt-get install -y wget tar
    elif [ -x "$(command -v yum)" ]; then
        # CentOS/RHEL
        echo "🔧 安装依赖 (yum)..."
        yum install -y wget tar
    elif [ -x "$(command -v dnf)" ]; then
        # Fedora
        echo "🔧 安装依赖 (dnf)..."
        dnf install -y wget tar
    elif [ -x "$(command -v zypper)" ]; then
        # openSUSE
        echo "🔧 安装依赖 (zypper)..."
        zypper install -y wget tar
    elif [ -x "$(command -v pacman)" ]; then
        # Arch
        echo "🔧 安装依赖 (pacman)..."
        pacman -Sy --noconfirm wget tar
    else
        echo "⚠️ 无法识别的包管理器，尝试继续执行..."
    fi
}

# 获取最新版本号
get_latest_version() {
    curl -sL https://api.github.com/repos/fatedier/frp/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# 检测系统架构
get_arch() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "arm" ;;
        armv6l)  echo "arm" ;;
        i386)    echo "386" ;;
        i686)    echo "386" ;;
        *)       echo "unsupported" ;;
    esac
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif type lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# 创建 systemd 服务
create_systemd_service() {
    SERVICE_FILE="/etc/systemd/system/frps.service"
    INSTALL_DIR=$(pwd)
    
    if [ -f "$SERVICE_FILE" ]; then
        echo "⚠️ 检测到已存在的服务文件: $SERVICE_FILE"
        read -p "是否覆盖？(y/N) " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[yY] ]]; then
            echo "跳过 systemd 服务创建。"
            return
        fi
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

    # 重新加载 systemd
    systemctl daemon-reload
    systemctl enable frps > /dev/null 2>&1
    
    echo "✅ systemd 服务创建完成！"
    echo "服务文件位置: $SERVICE_FILE"
    
    # 询问是否立即启动服务
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

# 检查 FRPS 是否安装
is_frps_installed() {
    [ -f "/etc/systemd/system/frps.service" ] && return 0
    [ -f "$(pwd)/frps" ] && [ -f "$(pwd)/frps.toml" ] && return 0
    return 1
}

# 显示服务状态
show_service_status() {
    if systemctl is-active frps > /dev/null 2>&1; then
        echo -e "🟢 FRPS 状态: ${GREEN}运行中${NC}"
    elif systemctl is-enabled frps > /dev/null 2>&1; then
        echo -e "🟡 FRPS 状态: ${YELLOW}已安装但未运行${NC}"
    else
        echo -e "🔴 FRPS 状态: ${RED}未安装或未配置${NC}"
    fi
}

# 管理菜单
show_management_menu() {
    clear
    echo -e "${BLUE}==============================${NC}"
    echo -e "${BLUE}      FRPS 服务管理菜单       ${NC}"
    echo -e "${BLUE}==============================${NC}"
    
    # 显示服务状态
    show_service_status
    
    echo ""
    
    # 根据状态显示不同颜色的选项
    if systemctl is-active frps > /dev/null 2>&1; then
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

# 卸载 FRPS
uninstall_frps() {
    echo "⚠️ 开始卸载 FRPS..."
    
    # 停止并禁用服务
    if systemctl is-active frps > /dev/null 2>&1; then
        systemctl stop frps
        echo "🛑 服务已停止"
    fi
    
    if systemctl is-enabled frps > /dev/null 2>&1; then
        systemctl disable frps
        echo "🔌 服务已禁用"
    fi
    
    # 删除服务文件
    SERVICE_FILE="/etc/systemd/system/frps.service"
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        echo "🗑️ 服务文件已删除"
        systemctl daemon-reload
    fi
    
    # 删除程序文件
    INSTALL_DIR=$(pwd)
    if [ -f "$INSTALL_DIR/frps" ]; then
        rm -f "$INSTALL_DIR/frps"
        echo "🗑️ 服务端程序已删除"
    fi
    
    # 删除配置文件（询问确认）
    if [ -f "$INSTALL_DIR/frps.toml" ]; then
        read -p "是否删除配置文件 frps.toml？(y/N) " DELETE_CONFIG
        if [[ "$DELETE_CONFIG" =~ ^[yY] ]]; then
            rm -f "$INSTALL_DIR/frps.toml"
            echo "🗑️ 配置文件已删除"
        else
            echo "🔒 保留配置文件: $INSTALL_DIR/frps.toml"
        fi
    fi
    
    echo -e "\n✅ FRPS 卸载完成！"
}

# 处理下载失败
handle_download_failure() {
    echo -e "\n❌ ${RED}下载失败！${NC}"
    echo "请手动下载 FRP 文件:"
    echo "  URL: $URL"
    echo "保存到当前目录后重新运行脚本"
    echo ""
    read -p "按任意键退出脚本..." -n1 -s
    exit 1
}

# 主安装函数
install_frps() {
    # 检测系统类型
    OS=$(detect_os)
    echo "💻 检测到系统: $OS"
    
    # 安装依赖
    install_dependencies
    
    # 获取版本和架构
    VERSION=$(get_latest_version)
    ARCH=$(get_arch)
    
    if [ "$ARCH" = "unsupported" ]; then
        echo "❌ 不支持的架构: $(uname -m)"
        exit 1
    fi

    FILENAME="frp_${VERSION}_linux_${ARCH}.tar.gz"
    URL="https://github.com/fatedier/frp/releases/download/v${VERSION}/${FILENAME}"

    echo "🔍 系统架构: ${ARCH}"
    echo "🆕 最新版本: v${VERSION}"
    echo "⏬ 下载 FRP..."
    
    # 尝试使用wget或curl下载
    if command -v wget &> /dev/null; then
        wget -q --show-progress "$URL" || handle_download_failure
    elif command -v curl &> /dev/null; then
        curl -LO --progress-bar "$URL" || handle_download_failure
    else
        echo "❌ 未找到wget或curl，无法下载"
        exit 1
    fi

    if [ ! -f "$FILENAME" ]; then
        handle_download_failure
    fi

    echo "📦 解压文件..."
    tar xzf "$FILENAME"
    
    # 修复目录名问题：新版本目录包含架构信息
    EXTRACTED_DIR="frp_${VERSION}_linux_${ARCH}"
    if [ ! -d "$EXTRACTED_DIR" ]; then
        # 尝试旧格式目录名
        EXTRACTED_DIR="frp_${VERSION}"
    fi
    
    if [ ! -d "$EXTRACTED_DIR" ]; then
        echo "❌ 解压目录未找到: $EXTRACTED_DIR"
        echo "💡 当前目录内容:"
        ls -l
        exit 1
    fi

    cd "$EXTRACTED_DIR" || exit

    echo "🧹 清理文件..."
    mv frps frps.toml ../
    cd ..
    
    echo "🧽 删除临时文件..."
    rm -rf "$EXTRACTED_DIR" "$FILENAME"

    echo -e "\n✅ FRP 服务端安装成功！"
    echo "======================================"
    echo "服务端文件: $(pwd)/frps"
    echo "配置文件:   $(pwd)/frps.toml"
    echo "======================================"
    
    # 配置 systemd 服务
    read -p "是否配置 systemd 服务以开机自启？(Y/n) " SETUP_SERVICE
    if [[ ! "$SETUP_SERVICE" =~ ^[nN] ]]; then
        create_systemd_service
    else
        echo -e "\n您可以使用以下命令手动启动:"
        echo "  $(pwd)/frps -c $(pwd)/frps.toml"
    fi
}

# 主函数
main() {
    # 检查是否已安装
    if is_frps_installed; then
        # 显示管理菜单
        while true; do
            show_management_menu
            read choice
            
            case $choice in
                1)
                    if systemctl is-active frps > /dev/null 2>&1; then
                        echo -e "${RED}❌ 服务已在运行中，无需启动${NC}"
                    else
                        systemctl start frps
                        echo -e "${GREEN}✅ 服务已启动${NC}"
                    fi
                    sleep 2
                    ;;
                2)
                    systemctl restart frps
                    echo -e "${YELLOW}🔄 服务已重启${NC}"
                    sleep 2
                    ;;
                3)
                    if systemctl is-active frps > /dev/null 2>&1; then
                        systemctl stop frps
                        echo -e "${RED}🛑 服务已停止${NC}"
                    else
                        echo -e "${YELLOW}⚠️ 服务未运行，无需停止${NC}"
                    fi
                    sleep 2
                    ;;
                4)
                    read -p "⚠️ 确定要卸载 FRPS 吗？(y/N) " CONFIRM_UNINSTALL
                    if [[ "$CONFIRM_UNINSTALL" =~ ^[yY] ]]; then
                        uninstall_frps
                        exit 0
                    else
                        echo "卸载已取消"
                    fi
                    sleep 2
                    ;;
                5)
                    echo "退出管理菜单"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}无效选择，请重新输入${NC}"
                    sleep 1
                    ;;
            esac
        done
    else
        # 未安装，执行安装流程
        install_frps
    fi
}

# 执行主函数
main