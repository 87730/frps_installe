#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

install_dependencies() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y wget curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y wget curl
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y wget curl
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Syu --noconfirm wget curl
    else
        echo -e "${RED}❌ 不支持的系统，无法安装依赖${NC}"
        exit 1
    fi
}

get_latest_version() {
    curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep 'tag_name' | cut -d '"' -f 4
}

get_arch() {
    case $(uname -m) in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l|armv6l) echo "arm" ;;
        i386|i686) echo "386" ;;
        *) echo "unsupported" ;;
    esac
}

is_frps_installed() {
    systemctl is-active frps >/dev/null 2>&1
}

show_service_status() {
    if is_frps_installed; then
        echo -e "${GREEN}🟢 FRPS 状态: 运行中${NC}"
    else
        echo -e "${RED}🔴 FRPS 状态: 已停止${NC}"
    fi
}

install_frps() {
    VERSION=$(get_latest_version)
    ARCH=$(get_arch)
    INSTALL_DIR="/opt/frps"
    FRP_URL="https://github.com/fatedier/frp/releases/download/${VERSION}/frp_${VERSION}_linux_${ARCH}.tar.gz"

    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR

    if [ -f frps ]; then
        echo -e "${YELLOW}⚠️ 检测到已存在 FRP 服务端，跳过下载${NC}"
    else
        echo -e "${BLUE}⬇️ 正在下载 FRP ${VERSION} ...${NC}"
        wget $FRP_URL
        tar -xzf frp_${VERSION}_linux_${ARCH}.tar.gz
        mv frp_${VERSION}_linux_${ARCH}/frps .
        rm -rf frp_${VERSION}_linux_${ARCH}*
    fi

    if [ -f frps.toml ]; then
        echo -e "${YELLOW}⚠️ 检测到已存在配置文件，跳过覆盖${NC}"
    else
        echo -e "${BLUE}📝 生成配置文件 frps.toml ...${NC}"
        cp frps.toml.example frps.toml
        TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
        sed -i "s/^token.*/token = \"$TOKEN\"/" frps.toml
        echo -e "${YELLOW}⚙️ 已生成初始配置文件 frps.toml，token 为 ${TOKEN}${NC}"
    fi

    read -p "请设置仪表盘密码 (默认: admin): " DASHBOARD_PASS
    DASHBOARD_PASS=${DASHBOARD_PASS:-admin}
    sed -i "s/dashboard_passwd.*/dashboard_passwd = \"$DASHBOARD_PASS\"/" frps.toml

    echo -e "${BLUE}🔒 配置 systemd 服务 ...${NC}"
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=FRP Server Service
After=network.target

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
    systemctl enable frps
    systemctl start frps

    echo -e "\n${GREEN}✅ FRP 服务端安装成功！${NC}"
    echo -e "${BLUE}服务端文件: ${GREEN}${INSTALL_DIR}/frps${BLUE}"
    echo -e "${BLUE}配置文件: ${GREEN}${INSTALL_DIR}/frps.toml${BLUE}"
    echo -e "${BLUE}防火墙设置：${NC}sudo ufw allow 7000/tcp"
    echo -e "${BLUE}   或：${NC}sudo firewall-cmd --permanent --add-port=7000/tcp && sudo firewall-cmd --reload"
    echo -e "${BLUE}仪表盘地址: ${GREEN}http://<服务器IP>:7500${BLUE} (用户名: admin, 密码: ${DASHBOARD_PASS})${NC}"
}

uninstall_frps() {
    echo -e "${BLUE}🗑️ 正在卸载 FRPS ...${NC}"
    systemctl stop frps
    systemctl disable frps
    rm -rf /etc/systemd/system/frps.service
    rm -rf /opt/frps*
    echo -e "${GREEN}✅ FRPS 已成功卸载${NC}"
}

show_menu() {
    while true; do
        clear
        echo -e "${BLUE}============================= FRPS 服务管理菜单 =============================${NC}"
        show_service_status
        echo -e "1. 启动服务"
        echo -e "2. 重启服务"
        echo -e "3. 停止服务"
        echo -e "4. 卸载 FRPS"
        echo -e "5. 退出"
        echo -e "${BLUE}================================================================================${NC}"
        read -p "请选择操作: " choice

        case $choice in
            1) systemctl start frps ;;
            2) systemctl restart frps ;;
            3) systemctl stop frps ;;
            4) uninstall_frps; exit ;;
            5) exit ;;
            *) echo -e "${RED}❌ 无效选项，请重试${NC}" ;;
        esac
    done
}

main() {
    if [ ! -f /opt/frps/frps ]; then
        install_frps
    else
        show_menu
    fi
}

if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        echo "🔔 非 root 用户，将尝试 sudo ..."
        exec sudo bash "$0" "$@"
    else
        echo "❌ 该脚本需要 root 权限，且系统未安装 sudo。"
        exit 1
    fi
fi

install_dependencies
main