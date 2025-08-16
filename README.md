##frp-server-installer/           
├──install_frps.sh # 主安装脚本        
├── README.md      # 项目说明文档
```

README.md 内容建议

```markdown
# FRP Server Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一键安装和管理FRP服务端的脚本，支持多种Linux发行版（Debian/Ubuntu/CentOS等）。

## 功能特点

- 自动检测系统架构和发行版
- 下载最新版FRP服务端
- 自动配置systemd服务
- 提供管理菜单（启动/停止/重启/卸载）
- 彩色状态显示（运行中/已停止/未安装）
- 彻底卸载功能

## 支持的系统

- Debian
- Ubuntu
- CentOS
- Fedora
- openSUSE
- Arch Linux

## 使用方法

### 全新安装

```bash
sudo -i
wget https://raw.githubusercontent.com/your-username/frp-server-installer/main/install_frps.sh
chmod +x install_frps.sh
./install_frps.sh
```

管理菜单

如果系统已安装FRPS，运行脚本将显示管理菜单：

```
==============================
      FRPS 服务管理菜单       
==============================
🟢 FRPS 状态: 运行中

1. 启动服务 (服务已运行)
2. 重启服务
3. 停止服务
4. 卸载 FRPS
5. 退出
==============================
```

卸载

通过管理菜单选择卸载选项，或手动运行：

```bash
systemctl stop frps
systemctl disable frps
rm /etc/systemd/system/frps.service
rm /path/to/frps /path/to/frps.toml  # 根据安装路径
