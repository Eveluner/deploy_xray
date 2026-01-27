# deploy_xray

🚀 **Xray VLESS 自动化部署工具包** - 一键部署 Xray VLESS 协议服务器，支持多用户管理、TLS 安全、systemd 自启

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📋 目录

- [功能特性](#功能特性)
- [脚本版本选择](#脚本版本选择)
- [快速开始](#快速开始)
- [详细使用指南](#详细使用指南)
- [脚本对比](#脚本对比)
- [系统要求](#系统要求)
- [故障排查](#故障排查)
- [常见问题](#常见问题)

---

## 🌟 功能特性

### 核心功能
- ✅ **自动化部署** - 一键部署 Xray VLESS 服务器
- ✅ **TLS 安全** - 支持 TLS 1.3 + XTLS-RPRX-Vision 流
- ✅ **自启动配置** - systemd 服务自动启动和重启
- ✅ **UUID 生成** - 自动生成客户端 UUID
- ✅ **多用户管理** - 支持添加、删除、管理多个客户端用户
- ✅ **用户追踪** - 自动标记初始用户和后续添加的用户
- ✅ **VLESS 链接生成** - 一键生成 VLESS 连接链接
- ✅ **配置持久化** - 用户信息保存到本地文件

### 高级功能（xray_vless_auto.sh）
- 🔧 **配置文件自动化** - 支持从配置文件自动读取参数，首次运行生成模板
- 🏷️ **备注作为链接名称** - 使用自定义备注作为 VLESS 链接的标识符
- 📋 **完整链接显示** - 用户列表中显示完整的 VLESS 连接链接

---

## 🔗 脚本版本选择

### 推荐使用

| 脚本 | 特点 | 适用场景 |
|------|------|--------|
| **xray_vless_auto.sh** | 配置文件支持、备注作链接名、自动化部署 | 📌 **推荐** - 批量部署、自动化环境 |
| **xray_vless_v2.sh** | 完整功能、无 Emoji、清晰文本标记 | 推荐 - 标准部署、所有终端兼容 |
| xray_vless_pro.sh | 完整功能、带 Emoji、优化菜单 | 可选 - 单个部署 |

### 其他版本（保留向后兼容）

| 脚本 | 说明 |
|------|------|
| xray_vless_plus_pro.sh | 扩展版本，功能同 xray_vless_pro.sh |
| xray_vless.sh | 原始版本，仅核心部署 |
| xray_vless_plus.sh | 原始扩展版本，基础用户管理 |

---

## 🚀 快速开始

### 方案 A：配置文件自动化部署（推荐）

**第一步：运行脚本生成配置文件**
```bash
bash xray_vless_auto.sh
# 脚本会自动检测并生成 /root/xray_install.conf
```

**第二步：编辑配置文件**
```bash
nano /root/xray_install.conf
```

**必填参数：**
```bash
DOMAIN="example.com"              # 你的域名
PORT="443"                        # 监听端口
CERT_FILE="/path/to/cert.pem"    # SSL 证书路径
KEY_FILE="/path/to/key.pem"      # SSL 私钥路径
```

**可选参数：**
```bash
XRAY_DIR="/root/xray"            # Xray 安装目录（默认）
XRAY_VERSION="26.1.23"           # Xray 版本（默认）
INITIAL_REMARK="我的设备"        # 初始用户备注（默认：自动生成）
INSTALL_SOURCE="github"          # 安装源：github 或自定义 URL
```

**第三步：再次运行脚本进行自动部署**
```bash
bash xray_vless_auto.sh
# 脚本会自动加载配置文件并完成部署
```

### 方案 B：交互式部署

```bash
bash xray_vless_v2.sh            # 推荐（无 Emoji）
# 或
bash xray_vless_pro.sh           # 可选（带 Emoji）
```

按照提示输入相关参数即可完成部署。

---

## 📖 详细使用指南

### 安装后的用户管理

部署完成后，使用 `xuser.sh` 管理用户：

```bash
bash /root/xuser.sh
```

**菜单选项：**

```
1) 添加用户
   - 输入用户备注
   - 自动生成 UUID
   - 生成 VLESS 链接

2) 删除用户
   - 输入要删除的用户 UUID
   - 从配置中移除该用户

3) 列出所有用户
   - 显示所有用户的备注、UUID 和完整 VLESS 链接
   - 示例输出：
     ┌─────────────────────────────────────────────┐
     │ 1. 备注: alice-phone                        │
     │    UUID: 12345678-abcd-efgh-ijkl-mnopqrst  │
     │    链接: vless://12345678@example.com:443?  │
     │           encryption=none&flow=xtls-rprx-  │
     │           vision&security=tls&type=tcp&    │
     │           sni=example.com#alice-phone      │
     └─────────────────────────────────────────────┘

4) 更新信息
   - 重新扫描配置文件
   - 更新 xray_info.txt

5) 卸载
   - 移除 systemd 服务
   - 删除 Xray 安装目录
   - 清理配置文件

0) 退出
```

### 生成的文件

部署完成后，以下文件会被创建：

```
/root/xray/                    # Xray 安装目录
├── config.json               # VLESS 协议配置
├── xray                       # Xray 二进制文件
└── ...

/root/xuser.sh               # 用户管理脚本

/root/xray_info.txt          # 用户信息和链接（文本格式）

/root/xray_install.conf      # 配置文件（auto 版本）

/etc/systemd/system/xray.service   # systemd 服务文件
```

### 服务管理

```bash
# 检查服务状态
systemctl status xray

# 启动服务
systemctl start xray

# 重启服务
systemctl restart xray

# 停止服务
systemctl stop xray

# 查看日志
journalctl -u xray -f
```

---

## 📊 脚本对比

| 功能特性 | xray_vless_auto.sh | xray_vless_v2.sh | xray_vless_pro.sh | xray_vless.sh |
|---------|:-:|:-:|:-:|:-:|
| 核心部署 | ✅ | ✅ | ✅ | ✅ |
| 多用户管理 | ✅ | ✅ | ✅ | ❌ |
| 配置文件支持 | ✅ | ❌ | ❌ | ❌ |
| 备注作链接名 | ✅ | ✅ | ✅ | ❌ |
| 自动化部署 | ✅ | ❌ | ❌ | ❌ |
| 初始用户标记 | ✅ | ✅ | ✅ | ❌ |
| Python3 JSON | ✅ | ✅ | ✅ | ❌ |
| sed 降级方案 | ✅ | ✅ | ✅ | ❌ |
| Emoji 指示符 | ❌ | ❌ | ✅ | ✅ |
| 兼容性 | 最佳 | 最佳 | 好 | 好 |

**推荐指数：** ⭐⭐⭐⭐⭐ xray_vless_auto.sh | ⭐⭐⭐⭐⭐ xray_vless_v2.sh

---

## 🖥️ 系统要求

- **操作系统** - Linux (Ubuntu 20.04+, CentOS 8+, Debian 11+ 等)
- **内核要求** - 支持 systemd
- **权限要求** - root 或 sudo 权限
- **网络** - 互联网连接（用于下载 Xray 和依赖）
- **磁盘空间** - 至少 100MB 可用空间

### 依赖项（脚本会自动安装）

- curl - 下载文件
- unzip - 解压 Xray 包
- python3（可选）- JSON 安全操作
- systemd - 服务管理

---

## 🔧 详细配置说明

### 配置文件格式 (xray_vless_auto.sh)

配置文件 `/root/xray_install.conf` 使用 bash 变量格式：

```bash
#!/bin/bash
# Xray VLESS 自动化部署配置文件

# ========== 必填参数 ==========

# 域名（必填）- 用于 TLS 证书的 SNI
DOMAIN="example.com"

# 监听端口（必填）- VLESS 协议监听的端口
PORT="443"

# SSL 证书文件路径（必填）
# 示例：/etc/letsencrypt/live/example.com/fullchain.pem
CERT_FILE="/path/to/your/certificate.pem"

# SSL 私钥文件路径（必填）
# 示例：/etc/letsencrypt/live/example.com/privkey.pem
KEY_FILE="/path/to/your/private-key.pem"

# ========== 可选参数 ==========

# Xray 安装目录（默认：/root/xray）
XRAY_DIR="/root/xray"

# Xray 版本（默认：26.1.23）
XRAY_VERSION="26.1.23"

# 初始用户备注（默认：自动生成）
INITIAL_REMARK="我的设备"

# 安装源（默认：github）
# 选项：github 或完整的下载 URL
INSTALL_SOURCE="github"

# 用户信息文件（默认：/root/xray_info.txt）
INFO_FILE="/root/xray_info.txt"

# 用户管理脚本路径（默认：/root/xuser.sh）
XUSER_SCRIPT="/root/xuser.sh"
```

### VLESS 协议配置详情

生成的 `config.json` 包含以下配置：

```json
{
  "log": {
    "loglevel": "info"
  },
  "inbound": {
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "UUID",
          "email": "用户备注"
        }
      ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls",
      "tlsSettings": {
        "certificateFile": "/path/to/cert.pem",
        "keyFile": "/path/to/key.pem"
      }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    }
  },
  "outbound": {
    "protocol": "freedom"
  }
}
```

### VLESS 连接链接格式

```
vless://UUID@domain:port?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=domain#备注
```

**链接组成部分：**
- `UUID` - 客户端唯一标识
- `domain:port` - 服务器地址和端口
- `encryption=none` - 不使用额外加密
- `flow=xtls-rprx-vision` - XTLS 流
- `security=tls` - TLS 安全
- `type=tcp` - TCP 传输
- `sni=domain` - TLS SNI
- `#备注` - 用户备注（链接标识符）

---

## 🐛 故障排查

### 问题 1：配置文件找不到（xray_vless_auto.sh）

**症状：** 脚本提示 `配置文件不存在`

**解决方案：**
```bash
# 首次运行会自动生成
bash xray_vless_auto.sh

# 检查配置文件是否存在
ls -la /root/xray_install.conf

# 如果不存在，手动复制示例
cp xray_install.conf.example /root/xray_install.conf
```

### 问题 2：Xray 启动失败

**症状：** `systemctl status xray` 显示 `inactive`

**解决方案：**
```bash
# 检查配置文件语法
/root/xray/xray run -test -config /root/xray/config.json

# 查看详细错误信息
journalctl -u xray -e

# 常见原因：
# - 证书/私钥路径错误
# - 端口已被占用
# - 权限问题
```

### 问题 3：证书不被信任

**症状：** 客户端连接时收到证书不信任警告

**解决方案：**
```bash
# 检查证书是否有效
openssl x509 -in /path/to/cert.pem -text -noout

# 确保使用完整证书链
# 对于 Let's Encrypt：
# - 使用 fullchain.pem（不是 cert.pem）
# - 私钥使用 privkey.pem
```

### 问题 4：Python3 不可用

**症状：** 脚本显示需要 Python3

**解决方案：**
```bash
# 脚本会自动降级到 sed 方案，无需操作
# 如果需要 Python3：
sudo apt update && sudo apt install python3  # Debian/Ubuntu
sudo yum install python3                     # CentOS/RHEL
```

### 问题 5：用户添加失败

**症状：** 运行 xuser.sh 添加用户失败

**解决方案：**
```bash
# 检查配置文件是否存在
ls -la /root/xray/config.json

# 检查权限
ls -la /root/xray/

# 确保 Xray 有权限读写配置文件
sudo chown -R root:root /root/xray/

# 检查 systemctl 是否能访问
systemctl is-active xray
```

---

## ❓ 常见问题

### Q: 这个项目是什么？

A: 这是一套自动化脚本，用于快速部署 Xray VLESS 协议服务器。它处理所有复杂的配置和设置，让你只需填写几个参数即可拥有一个可用的 VLESS 服务器。

### Q: 哪个脚本最适合我？

A: 
- **如果你需要批量部署或自动化** → 使用 `xray_vless_auto.sh`
- **如果你是第一次部署或只需标准功能** → 使用 `xray_vless_v2.sh`
- **如果你的终端支持 Emoji** → 使用 `xray_vless_pro.sh`

### Q: 可以添加多少个用户？

A: 理论上无限制，受系统资源和网络带宽限制。每个用户对应一个 UUID，配置文件中可以存储任意数量的 UUID。

### Q: 可以修改端口吗？

A: 可以。修改 `/root/xray/config.json` 中的 `inbound.port`，然后重启服务：
```bash
systemctl restart xray
```

### Q: 脚本支持 IPv6 吗？

A: 脚本本身支持 IPv6，但需要在配置中指定 IPv6 地址或域名，且确保防火墙允许 IPv6 连接。

### Q: 可以在同一台服务器上运行多个实例吗？

A: 可以，但需要使用不同的端口和配置文件。建议将 Xray 目录更改为不同路径。

### Q: 如何备份配置？

A: 备份以下文件：
```bash
# 备份配置
cp /root/xray/config.json /backup/config.json.bak

# 备份用户信息
cp /root/xray_info.txt /backup/xray_info.txt.bak
```

### Q: 如何卸载？

A: 使用 xuser.sh 的卸载功能，或手动执行：
```bash
# 停止服务
systemctl stop xray

# 禁用自启
systemctl disable xray

# 删除服务文件
rm /etc/systemd/system/xray.service

# 删除 Xray 目录
rm -rf /root/xray

# 删除脚本和信息文件
rm /root/xuser.sh /root/xray_info.txt
```

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

## 📞 技术支持

- 📋 查看 [故障排查](#故障排查) 部分
- 💬 提交 GitHub Issue
- 📖 查看脚本注释和示例配置

---

**最后更新：** 2026 年 1 月 27 日
