#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}❌ 该脚本需要root权限，请使用sudo或切换到root用户${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}🔄 检查并安装必要依赖...${NC}"
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

# 检查FRPS是否已安装
is_frps_installed() {
    [ -f /opt/frps/frps ] && systemctl is-active frps >/dev/null 2>&1
}

# 显示服务状态
show_service_status() {
    if is_frps_installed; then
        echo -e "${GREEN}🟢 FRPS 状态: 运行中${NC}"
    else
        echo -e "${RED}🔴 FRPS 状态: 未安装或已停止${NC}"
    fi
}

# 安装FRPS
install_frps() {
    clear
    echo -e "${BLUE}============================= 开始安装 FRPS =============================${NC}"
    
    # 获取最新版本和架构
    VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep 'tag_name' | cut -d '"' -f 4)
    ARCH=$(get_arch)
    INSTALL_DIR="/opt/frps"
    FRP_URL="https://github.com/fatedier/frp/releases/download/${VERSION}/frp_${VERSION}_linux_${ARCH}.tar.gz"

    # 创建安装目录
    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR

    # 下载并解压
    echo -e "${BLUE}⬇️ 正在下载 FRP ${VERSION} ...${NC}"
    wget $FRP_URL
    tar -xzf frp_${VERSION}_linux_${ARCH}.tar.gz
    mv frp_${VERSION}_linux_${ARCH}/frps .
    rm -rf frp_${VERSION}_linux_${ARCH}*

    # 生成配置文件
    echo -e "${BLUE}📝 生成配置文件 frps.toml ...${NC}"
    cp frps.toml.example frps.toml
    TOKEN=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    sed -i "s/^token.*/token = \"$TOKEN\"/" frps.toml

    # 设置仪表盘密码
    read -p "请设置仪表盘密码 (默认: admin): " DASHBOARD_PASS
    DASHBOARD_PASS=${DASHBOARD_PASS:-admin}
    sed -i "s/dashboard_passwd.*/dashboard_passwd = \"$DASHBOARD_PASS\"/" frps.toml

    # 配置systemd服务
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

    # 启动服务
    systemctl daemon-reload
    systemctl enable frps
    systemctl start frps

    # 显示安装信息
    clear
    echo -e "\n${GREEN}✅ FRP 服务端安装成功！${NC}"
    echo -e "${BLUE}服务端文件: ${GREEN}${INSTALL_DIR}/frps${BLUE}"
    echo -e "${BLUE}配置文件: ${GREEN}${INSTALL_DIR}/frps.toml${BLUE}"
    echo -e "${BLUE}防火墙设置：${NC}sudo ufw allow 7000/tcp"
    echo -e "${BLUE}   或：${NC}sudo firewall-cmd --permanent --add-port=7000/tcp && sudo firewall-cmd --reload"
    echo -e "${BLUE}仪表盘地址: ${GREEN}http://<服务器IP>:7500${BLUE} (用户名: admin, 密码: ${DASHBOARD_PASS})${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    read -p "按回车键返回主菜单..."
}

# 卸载FRPS
uninstall_frps() {
    clear
    echo -e "${BLUE}============================= 确认卸载 FRPS =============================${NC}"
    echo -e "${YELLOW}⚠️ 卸载将执行以下操作：${NC}"
    echo -e "1. 停止 FRPS 服务"
    echo -e "2. 禁用 FRPS 开机自启"
    echo -e "3. 删除 FRPS 服务配置"
    echo -e "4. 清理 FRPS 安装文件"
    echo -e "${RED}❌ 卸载后所有内网穿透功能将不可用${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    
    read -p "确定要卸载 FRPS 吗？(y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        return
    fi

    echo -e "${BLUE}🗑️ 正在卸载 FRPS ...${NC}"
    systemctl stop frps
    systemctl disable frps
    rm -rf /etc/systemd/system/frps.service
    rm -rf /opt/frps*
    
    echo -e "${GREEN}✅ FRPS 已成功卸载${NC}"
    echo -e "${BLUE}================================================================================${NC}"
    read -p "按回车键返回主菜单..."
}

# 服务管理菜单
manage_service() {
    while true; do
        clear
        echo -e "${BLUE}============================= FRPS 服务管理 =============================${NC}"
        show_service_status
        echo -e "1. 启动服务"
        echo -e "2. 重启服务"
        echo -e "3. 停止服务"
        echo -e "4. 返回主菜单"
        echo -e "${BLUE}================================================================================${NC}"
        read -p "请选择操作: " choice

        case $choice in
            1) systemctl start frps ;;
            2) systemctl restart frps ;;
            3) systemctl stop frps ;;
            4) return ;;
            *) echo -e "${RED}❌ 无效选项，请重试${NC}" ;;
        esac
    done
}

# 主菜单
main_menu() {
    while true; do
        clear
       