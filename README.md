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
# deploy_xray

轻量的 Xray VLESS 一键部署与用户管理脚本集合，用于在支持 systemd 的 Linux 主机上快速部署 Xray 服务并生成 VLESS 链接。

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

概览：本仓库包含若干用于不同场景的部署脚本（从简单交互式到生产级自动化、支持 ECH、流量限速与 API 统计），并在安装后生成 `xuser.sh` 管理脚本用于添加/删除/列出用户。

主要文件
- `xray_vless.sh` — 最简单的交互式安装脚本，逐步询问下载源、端口、域名与证书，生成 `config.json` 与 systemd 服务。
- `xray_vless_pro.sh` — 增强版交互脚本，生成带 `email` 字段的初始用户并自动写入 `xuser.sh`（带 Python3 回退），保存环境变量到 `/root/.xray_env`。
- `xray_vless_auto.sh` — 基于配置文件的自动安装器（配置模板见 `xray_install.conf.example`），适合批量或无人值守部署，会生成 `xuser.sh` 和 `xray_info.txt`。
- `xray_vless_auto_2.sh` — `xray_vless_auto.sh` 的扩展，增加了可通过脚本管理 Xray 服务（启动/停止/更新）和更多菜单选项。
- `xray_vless_auto_3.sh` — 更健壮的自动化版本（推荐用于生产）：严格的输入校验、架构检测、原子写入、内置 Python3 JSON 操作、自动检测并安装依赖、生成安全的 systemd unit、写入环境文件并生成 `xuser.sh`。
- `xray_vless_auto_ech.sh` — 支持 ECH 的自动化脚本，允许在配置中启用 ECH（可选）并把 ECH 状态写入 `xray_info.txt`。
- `xray_vless_auto_limit.sh` — 支持流量统计与限速的扩展脚本，启用 Xray API（本地绑定）用于收集统计并在 `xuser.sh` 中提供限流管理功能。
- `xray_install.conf.example` — 自动化脚本的配置文件示例（复制并填写为 `/root/xray_install.conf`）。

快速开始（推荐）
- 生成并编辑配置模板：
  ```bash
  bash xray_vless_auto_3.sh  # 首次运行会生成配置模板（默认 /root/xray_install.conf）
  cp xray_install.conf.example /root/xray_install.conf
  nano /root/xray_install.conf
  ```
- 填写必填项（`DOMAIN`, `PORT`, `CERT_FILE`, `KEY_FILE`），保存后再次运行：
  ```bash
  bash xray_vless_auto_3.sh /root/xray_install.conf
  ```
- 部署完成后：
  - 用户管理脚本：`/root/xuser.sh`（或根据配置的路径）
  - 用户信息与链接：`/root/xray_info.txt`
  - Xray 安装目录（默认）：`/root/xray`

选择建议
- 开发/测试：使用 `xray_vless.sh` 或 `xray_vless_pro.sh` 交互安装。
- 无人值守/生产：优先使用 `xray_vless_auto_3.sh`（更严谨的校验和原子操作）。
- 需要 ECH：使用 `xray_vless_auto_ech.sh` 并在配置中启用 `USE_ECH`。
- 需要用户流量统计/限速：使用 `xray_vless_auto_limit.sh`（启用 API 并配置 `API_PORT`）。

系统要求与依赖
- 操作系统：支持 systemd 的 Linux 发行版（Ubuntu/CentOS/Debian 等）。
- 权限：需 root 或 sudo 权限。
- 依赖：`curl`, `unzip`, `python3`（部分脚本对 Python3 有依赖，但均提供 sed 回退）。

安全与注意事项
- 请确保 `CERT_FILE` 使用完整证书链（Let's Encrypt 使用 `fullchain.pem`）。
- 请勿把配置或私钥文件保存在不受信任的位置。自动化脚本会把部分环境信息写到 `/root/.xray_env`，请按需保护该文件权限。
- `xray_vless_auto_3.sh` 在写配置时使用原子替换策略以减少因意外中断导致的配置损坏。

贡献与问题
- 发现问题或功能建议，请在仓库中打开 issue。

许可证
- 本项目采用 Apache License 2.0，详见 `LICENSE`。
