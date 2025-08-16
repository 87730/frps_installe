#!/bin/bash
# ------------------------------------------------------------
#  frps 一键安装脚本（修正版）
#  适用于主流 Linux 发行版（amd64/arm64/armv7）
# ------------------------------------------------------------

# 1. 权限检查：root 或具备 sudo
if [[ $EUID -ne 0 ]]; then
   if command -v sudo >/dev/null 2>&1; then
       echo "检测到非 root 用户，将尝试使用 sudo ..."
       exec sudo bash "$0" "$@"
   else
       echo "❌ 需要 root 权限，且系统未安装 sudo。"
       exit 1
   fi
fi

# 2. 颜色输出
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# 3. 安装依赖
install_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y wget tar curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget tar curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y wget tar curl
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm wget tar curl
    else
        echo "⚠️ 无法识别包管理器，请手动安装 wget tar curl"
    fi
}

# 4. 获取最新版本
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
