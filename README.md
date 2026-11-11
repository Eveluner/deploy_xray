# deploy_xray

本项目提供一组用于 Linux 的 Xray VLESS 部署脚本。主脚本 `xray_vless_auto.sh` 根据配置文件中的参数安装 Xray、生成配置并设置 systemd 服务，同时输出 VLESS 连接信息和用户管理脚本。

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## 功能

- 自动安装 Xray，生成 VLESS + TLS 配置。
- 创建并启用 systemd 服务。
- 生成客户端 UUID、VLESS 链接和用户信息文件。
- 通过 `xuser.sh` 管理用户及 Xray 服务。
- 支持从 GitHub 下载、使用自定义下载链接，或从本地 ZIP 文件安装。

## 快速开始

### 1. 准备配置文件

首次运行会在默认位置 `/root/xray_install.conf` 生成配置模板：

```bash
bash xray_vless_auto.sh
```

也可以指定配置文件路径：

```bash
bash xray_vless_auto.sh /path/to/xray_install.conf
```

编辑生成的配置文件，至少设置以下参数：

```bash
DOMAIN="example.com"
PORT="443"
CERT_FILE="/path/to/fullchain.pem"
KEY_FILE="/path/to/privkey.pem"
```

`DOMAIN` 必须与证书中的域名匹配。使用 Let's Encrypt 证书时，通常应将 `CERT_FILE` 指向 `fullchain.pem`。

### 2. 执行部署

```bash
bash xray_vless_auto.sh /root/xray_install.conf
```

脚本会校验配置、检查并安装所需依赖、安装 Xray、验证生成的 Xray 配置，然后创建并启动 systemd 服务。部署成功后，终端会显示初始用户的 VLESS 链接。

### 3. 管理用户和服务

```bash
bash /root/xuser.sh
```

`xuser.sh` 将操作分为“用户操作”和“Xray 操作”两个菜单。你可以添加、删除或查看用户，也可以更新用户信息、查看服务日志、启停或重启服务、更新 Xray 或卸载服务。常用的 systemd 命令如下：

```bash
systemctl status xray
systemctl restart xray
journalctl -u xray -f
```

如果将 `SERVICE_NAME` 设置为其他值，请相应替换命令中的 `xray`。

## 入口服务器（中转）部署

`xray_vless_relay.sh` 用于部署独立的入口服务器，不会修改 `xray_vless_auto.sh`。入口服务器接收客户端的 VLESS + TLS/TCP 连接，并将流量转发至指定的出口 VLESS 节点。本脚本要求出口节点使用 VLESS + TLS/TCP。

首次运行会生成独立配置文件 `/root/xray_relay_install.conf`：

```bash
bash xray_vless_relay.sh
```

填写入口域名、端口、证书以及出口节点信息，然后运行部署命令：

```bash
bash xray_vless_relay.sh /root/xray_relay_install.conf
```

出口节点的必填参数为 `UPSTREAM_ADDRESS`、`UPSTREAM_PORT`、`UPSTREAM_UUID` 和 `UPSTREAM_SNI`。`UPSTREAM_FLOW` 默认为 `xtls-rprx-vision`；如果出口节点未配置 flow，可将其设为空。入口服务器生成的客户端连接信息保存在部署信息文件中。

中转部署默认使用独立的文件和服务：`/root/xray_relay/`、`/root/xray_relay_info.txt`、`/root/xuser_relay.sh` 和 `xray-relay.service`，因此可与原脚本部署的 `xray.service` 同时运行。使用以下命令管理入口用户和服务：

```bash
bash /root/xuser_relay.sh
systemctl status xray-relay
```

## 配置参数

配置文件采用 Bash 变量格式。可根据需要调整路径和选项；未指定的可选参数将使用默认值。

下表列出 `xray_vless_auto.sh` 支持的参数及默认值。入口服务器脚本使用的独立路径和上游参数另列于下表。

| 参数 | 说明 | 默认值 |
|---|---|---|
| `DOMAIN` | 服务器域名，必填 | — |
| `PORT` | 监听端口，范围为 1–65535，必填 | — |
| `CERT_FILE` | TLS 证书文件路径，必填 | — |
| `KEY_FILE` | TLS 私钥文件路径，必填 | — |
| `XRAY_DIR` | Xray 安装目录 | `/root/xray` |
| `XRAY_ARCH` | 发布包架构；设为 `auto` 时自动检测 | `auto` |
| `VLESS_FLOW` | VLESS flow | `xtls-rprx-vision` |
| `INITIAL_REMARK` | 初始用户备注 | `初始用户` |
| `INSTALL_SOURCE` | 安装来源：`1` GitHub 最新版、`2` 自定义链接、`3` 本地 ZIP | `1` |
| `XRAY_URL` | `INSTALL_SOURCE=2` 时使用的下载链接 | 空 |
| `XRAY_ZIP_LOCAL` | `INSTALL_SOURCE=3` 时使用的本地 ZIP 路径 | 空 |
| `INFO_FILE` | 用户信息文件路径 | `/root/xray_info.txt` |
| `XUSER_SCRIPT` | 用户管理脚本路径 | `/root/xuser.sh` |
| `XRAY_ENV_FILE` | 管理脚本使用的环境文件 | `/root/.xray_env` |
| `SYSTEMD_DIR` | systemd unit 文件目录 | `/etc/systemd/system` |
| `SERVICE_NAME` | systemd 服务名称 | `xray` |

`XRAY_ARCH` 可设置为 `64`、`arm64-v8a`、`arm32-v7a` 等 Xray 发布包架构名。使用本地 ZIP 安装时，压缩包中必须包含 `xray` 可执行文件。

入口服务器脚本另外使用以下出口节点参数：

| 参数 | 说明 | 默认值 |
|---|---|---|
| `UPSTREAM_ADDRESS` | 出口服务器域名或 IP | 空，必填 |
| `UPSTREAM_PORT` | 出口服务器 VLESS 端口 | 空，必填 |
| `UPSTREAM_UUID` | 出口服务器分配的 UUID | 空，必填 |
| `UPSTREAM_SNI` | 出口 TLS SNI | 默认使用 `UPSTREAM_ADDRESS` |
| `UPSTREAM_FLOW` | 出口 VLESS flow | `xtls-rprx-vision` |

## 部署文件

默认部署会创建以下文件：

| 路径 | 用途 |
|---|---|
| `/root/xray/` | Xray 程序及 `config.json` |
| `/root/xuser.sh` | 用户和服务管理脚本 |
| `/root/xray_info.txt` | 用户信息与 VLESS 链接 |
| `/root/.xray_env` | 管理脚本所需的环境参数 |
| `/etc/systemd/system/xray.service` | systemd 服务配置 |

实际路径以配置文件中的设置为准。

## 系统要求

- 支持 systemd 的 Linux 系统。
- root 权限。
- Python 3、curl 和 unzip。脚本会检查这些依赖，并尝试通过支持的包管理器安装缺少的依赖。
- 从 GitHub 或自定义链接下载时需要网络连接。

## 安全提示

- 配置文件采用 Bash 变量格式，并会由脚本加载。请只使用可信来源的配置文件，避免执行来源不明的内容。
- 妥善保管 TLS 私钥，以及包含服务器参数的配置文件和环境文件。
- 部署前请确认 `XRAY_DIR` 指向专用目录。卸载时会删除该目录及相关部署文件。
- 如果已有 Xray 配置，请在部署前备份重要数据。

## 常见问题

**脚本提示配置文件不存在或生成了模板**

首次运行会生成配置模板。填写 `DOMAIN`、`PORT`、`CERT_FILE` 和 `KEY_FILE` 后，重新运行部署命令即可。

**配置校验或服务启动失败**

请检查证书和私钥路径、端口占用情况及配置值，再运行 `systemctl status xray` 和 `journalctl -u xray -n 100 --no-pager` 查看错误信息。

**无法自动识别架构**

请在配置文件中手动设置与系统及 Xray 发布包匹配的 `XRAY_ARCH`。

## 许可证

本项目使用 Apache License 2.0，详见 [LICENSE](LICENSE)。
