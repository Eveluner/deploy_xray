#!/bin/bash
set -e

# 配置文件路径
CONFIG_FILE_PATH="${1:-/root/xray_install.conf}"

# 配置文件处理函数
load_config() {
  if [ -f "$CONFIG_FILE_PATH" ]; then
  # 生成 UUID
  UUID="$($BIN uuid)"

  # 如果系统有 python3，可用 Python 进行安全的 JSON 操作，避免用户备注包含
  # 引号、反斜杠等字符导致配置损坏。
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$REMARK" "$UUID" <<'PY'
import sys, json
config_path = "$CONFIG_FILE"
remark = sys.argv[1]
uuid = sys.argv[2]
try:
    with open(config_path, 'r') as f:
        cfg = json.load(f)
    clients = cfg['inbounds'][0]['settings']['clients']
    # 重复检查
    if any(c.get('email') == remark for c in clients):
        print('[ERR] 备注已存在')
        sys.exit(1)
    clients.append({'id': uuid, 'flow': 'xtls-rprx-vision', 'email': remark})
    with open(config_path, 'w') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    print('[OK] 添加成功')
    print(f'备注: {remark}')
    print(f'UUID: {uuid}')
except Exception as e:
    print(f'[ERR] {e}')
    sys.exit(1)
PY
    if [ $? -ne 0 ]; then
      return 1
    fi
  else
    # 旧版 sed 插入方法 (仍保留以便没有 Python 的系统使用)
    if grep -q "\"email\": \"$REMARK\"" "$CONFIG_FILE"; then
      echo "[ERR] 备注已存在"
      return 1
    fi

    sed -i "/\"clients\": \[/a\\          {\n            \"id\": \"$UUID\",\n            \"flow\": \"xtls-rprx-vision\",\n            \"email\": \"$REMARK\"\n          }," "$CONFIG_FILE"

    echo "[OK] 添加成功"
    echo "备注: $REMARK"
    echo "UUID: $UUID"
  fi

  # 验证配置
  if ! "$BIN" run -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "[ERR] 配置验证失败，回滚更改..."
    git -C "$(dirname $CONFIG_FILE)" checkout "$CONFIG_FILE" 2>/dev/null || true
    return 1
  fi

# 可选项（默认值已预设）
XRAY_DIR="/root/xray"
XRAY_VERSION="26.1.23"
VLESS_FLOW="xtls-rprx-vision"
INITIAL_REMARK="初始用户"

# 下载方式：1=GitHub推荐版本, 2=自定义URL, 3=本地文件
INSTALL_SOURCE="1"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v26.1.23/Xray-linux-64.zip"
XRAY_ZIP_LOCAL=""

# 信息文件保存路径
INFO_FILE="/root/xray_info.txt"
XUSER_SCRIPT="/root/xuser.sh"
CONFIGEOF

  echo "[OK] 已生成配置文件模板: $template_path"
  echo "请编辑配置文件并填写参数后，再次运行本脚本"
  echo ""
  echo "关键参数说明:"
  echo "  DOMAIN        - 服务器域名（必填）"
  echo "  PORT          - 监听端口（必填）"
  echo "  CERT_FILE     - SSL 证书文件路径（必填）"
  echo "  KEY_FILE      - SSL 私钥文件路径（必填）"
  echo ""
}

echo "========== Xray VLESS 自动部署脚本 =========="

# 检查是否需要交互式配置
if [ ! -f "$CONFIG_FILE_PATH" ]; then
  echo "==> 首次运行，需要配置"
  read -p "请输入配置文件保存路径 [默认 $CONFIG_FILE_PATH]: " custom_path
  if [ -n "$custom_path" ]; then
    CONFIG_FILE_PATH="$custom_path"
  fi
  
  generate_config_template
  exit 0
fi

# 尝试加载配置
if ! load_config; then
  generate_config_template
  exit 0
fi

# 验证必填配置
if [ -z "$DOMAIN" ] || [ -z "$PORT" ] || [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ]; then
  echo "[ERR] 配置文件中缺少必填参数"
  echo "请编辑 $CONFIG_FILE_PATH 并填写以下必填项:"
  echo "  - DOMAIN: 服务器域名"
  echo "  - PORT: 监听端口"
  echo "  - CERT_FILE: 证书路径"
  echo "  - KEY_FILE: 私钥路径"
  exit 1
fi

# 使用配置中的值覆盖默认值
XRAY_DIR="${XRAY_DIR:-/root/xray}"
INFO_FILE="${INFO_FILE:-/root/xray_info.txt}"
XUSER_SCRIPT="${XUSER_SCRIPT:-/root/xuser.sh}"

### 0. 环境 & 依赖检查
echo "==> 检测运行环境"

if ! command -v systemctl >/dev/null 2>&1; then
  echo "[ERR] 当前系统不支持 systemd"
  exit 1
fi

install_pkg() {
  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$@"
  else
    echo "[ERR] 不支持的包管理器"
    exit 1
  fi
}

for pkg in curl unzip; do
  if ! command -v $pkg >/dev/null 2>&1; then
    echo "==> 安装依赖: $pkg"
    install_pkg $pkg
  fi
done

### 1. 选择 Xray 来源
echo
echo "==> 下载和安装 Xray"

# 如果使用配置文件，直接使用配置中的安装源
if [ "$INSTALL_SOURCE" = "1" ]; then
  XRAY_URL="${XRAY_URL:-https://github.com/XTLS/Xray-core/releases/download/v26.1.23/Xray-linux-64.zip}"
  echo "==> 下载 Xray 26.1.23"
elif [ "$INSTALL_SOURCE" = "2" ]; then
  XRAY_URL="${XRAY_URL:-https://github.com/XTLS/Xray-core/releases/download/v26.1.23/Xray-linux-64.zip}"
  echo "==> 使用自定义 URL: $XRAY_URL"
elif [ "$INSTALL_SOURCE" = "3" ]; then
  if [ -z "$XRAY_ZIP_LOCAL" ]; then
    echo "[ERR] 配置文件中未指定本地压缩文件路径"
    exit 1
  fi
  echo "==> 使用本地文件: $XRAY_ZIP_LOCAL"
else
  echo "[ERR] 未知的安装源设置"
  exit 1
fi

TMP_DIR="/tmp/xray_install"
mkdir -p $TMP_DIR
cd $TMP_DIR

if [ "$INSTALL_SOURCE" = "3" ]; then
  cp "$XRAY_ZIP_LOCAL" xray.zip
else
  curl -L -o xray.zip "$XRAY_URL"
fi

### 2. 安装位置
mkdir -p "$XRAY_DIR"
unzip -o xray.zip -d "$XRAY_DIR"
chmod +x "$XRAY_DIR/xray"

echo "==> Xray 版本确认"
"$XRAY_DIR/xray" version

### 3. 生成配置（UUID 自动生成）
UUID=$("$XRAY_DIR/xray" uuid)

# 从配置文件读取参数（已在开始时加载）
# PORT、DOMAIN、CERT、KEY 已从配置文件读取
CERT="$CERT_FILE"
KEY="$KEY_FILE"

# 检查证书和密钥文件是否存在
if [ ! -f "$CERT" ]; then
  echo "[ERR] 证书文件不存在: $CERT"
  exit 1
fi
if [ ! -f "$KEY" ]; then
  echo "[ERR] 私钥文件不存在: $KEY"
  exit 1
fi

CONFIG_FILE="$XRAY_DIR/config.json"

echo "==> 使用配置参数:"
echo "    域名: $DOMAIN"
echo "    端口: $PORT"
echo "    证书: $CERT"
echo "    私钥: $KEY"
echo "    Xray 目录: $XRAY_DIR"
echo ""

cat > "$CONFIG_FILE" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-vision",
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision",
            "email": "初始用户"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$DOMAIN",
          "certificates": [
            {
              "certificateFile": "$CERT",
              "keyFile": "$KEY"
            }
          ],
          "minVersion": "1.3",
          "cipherSuites": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384",
          "alpn": ["h2"],
          "preferServerCipherSuites": false,
          "rejectUnknownSni": false
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpKeepAliveIdle": 60,
          "tcpNoDelay": true
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

### 4. 配置检查
echo "==> 校验配置文件"
"$XRAY_DIR/xray" run -test -config "$CONFIG_FILE"

### 5. systemd 服务
SERVICE_FILE="/etc/systemd/system/xray.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
ExecStart=$XRAY_DIR/xray run -config $CONFIG_FILE
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

### 6. 生成链接并保存
# 使用备注作为链接名字
INITIAL_REMARK="${INITIAL_REMARK:-初始用户}"
VLESS_LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=$DOMAIN#$INITIAL_REMARK"

cat > "$INFO_FILE" << EOF
Xray 安装目录: $XRAY_DIR
Xray 版本: ${XRAY_VERSION:-26.1.23}
域名: $DOMAIN
端口: $PORT

VLESS 连接信息:
================

备注: 初始用户
UUID: $UUID
VLESS 链接: $VLESS_LINK
EOF

echo
echo "========== 部署完成 =========="
echo "$VLESS_LINK"
echo "已保存到: $INFO_FILE"

### 7. 生成 xuser.sh（用户管理脚本）

cat > "$XUSER_SCRIPT" << 'EOFXUSER'
#!/bin/bash
set -e
set +H

# ==========================
# Xray 用户管理脚本 xuser.sh
# ==========================

XRAY_DIR="${XRAY_DIR:-/root/xray}"
CONFIG_FILE="${CONFIG_FILE:-$XRAY_DIR/config.json}"
BIN="${BIN:-$XRAY_DIR/xray}"
INFO_FILE="${INFO_FILE:-/root/xray_info.txt}"

# 从 xray_info.txt 获取 domain 和 port
get_domain() { 
  grep "^域名:" "$INFO_FILE" 2>/dev/null | tail -1 | awk -F": " '{print $2}' || echo ""
}

get_port() { 
  grep "^端口:" "$INFO_FILE" 2>/dev/null | tail -1 | awk -F": " '{print $2}' || echo ""
}

# 从 xray_info.txt 获取 Xray 安装目录
get_xray_dir() {
  grep "^Xray 安装目录:" "$INFO_FILE" 2>/dev/null | tail -1 | awk -F": " '{print $2}' || echo "/root/xray"
}

# 更新 xray_info.txt 文件
update_info() {
  DOMAIN="$(get_domain)"
  PORT="$(get_port)"
  XRAY_DIR="$(get_xray_dir)"

  # 如果 DOMAIN 或 PORT 为空，返回错误
  if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
    echo "[ERR] 无法从 xray_info.txt 读取域名或端口"
    return 1
  fi

  cat > "$INFO_FILE" << EOF
Xray 安装目录: $XRAY_DIR
Xray 版本: 26.1.23
域名: $DOMAIN
端口: $PORT

VLESS 连接信息:
================

EOF

  # 从配置中提取用户信息
  awk -v domain="$DOMAIN" -v port="$PORT" '
    /"id":/ { 
      id=$2; 
      gsub(/[",]/, "", id);
      client_id=id;
    }
    /"email":/ { 
      email=$2; 
      gsub(/[",]/, "", email);
      if (client_id != "") {
        printf "备注: %s\n", email;
        printf "UUID: %s\n", client_id;
        printf "VLESS 链接: vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=%s#%s\n\n", client_id, domain, port, domain, email;
        client_id="";
      }
    }
  ' DOMAIN="$DOMAIN" PORT="$PORT" "$CONFIG_FILE" >> "$INFO_FILE"
}

# 添加用户
add_user() {
  read -p "请输入用户备注（例如: alice-iphone）: " REMARK
  if [ -z "$REMARK" ]; then
    echo "[ERR] 备注不能为空"
    return 1
  fi

  # 检查备注是否已存在
  if grep -q "\"email\": \"$REMARK\"" "$CONFIG_FILE"; then
    echo "[ERR] 备注已存在"
    return 1
  fi

  # 生成 UUID
  UUID="$($BIN uuid)"

  # 向 clients 数组中插入新用户
  # 找到最后一个 client 并在其后添加逗号和新 client
  sed -i "/\"clients\": \[/a\\          {\n            \"id\": \"$UUID\",\n            \"flow\": \"xtls-rprx-vision\",\n            \"email\": \"$REMARK\"\n          }," "$CONFIG_FILE"

  echo "[OK] 添加成功"
  echo "备注: $REMARK"
  echo "UUID: $UUID"

  # 验证配置
  if ! "$BIN" run -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "[ERR] 配置验证失败，回滚更改..."
    git -C "$(dirname $CONFIG_FILE)" checkout "$CONFIG_FILE" 2>/dev/null || true
    return 1
  fi

  update_info
  systemctl restart xray
  echo "[OK] Xray 已重启"
}

# 删除用户
del_user() {
  echo "=== 删除用户 ==="
  list_user
  echo
  read -p "请输入要删除的 UUID 或备注: " KEY
  if [ -z "$KEY" ]; then
    echo "取消"
    return 0
  fi

  # 检查用户是否存在
  if ! grep -q "$KEY" "$CONFIG_FILE"; then
    echo "[ERR] 找不到用户"
    return 1
  fi

  # 删除包含该 KEY 的整个 client 对象（多行）
  # 使用更安全的方式处理多行对象
  python3 -c "
import json
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    # 在 clients 中查找并删除
    original_count = len(config['inbounds'][0]['settings']['clients'])
    config['inbounds'][0]['settings']['clients'] = [
        c for c in config['inbounds'][0]['settings']['clients']
        if c.get('id') != '$KEY' and c.get('email') != '$KEY'
    ]
    
    if len(config['inbounds'][0]['settings']['clients']) == original_count:
        print('[ERR] 找不到用户')
        sys.exit(1)
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    
    print('[OK] 删除成功')
except Exception as e:
    print(f'[ERR] 错误: {e}')
    sys.exit(1)
  " 2>/dev/null || {
    # 如果 python3 不可用，使用 sed 方法（不安全但能用）
    sed -i "/\"id\": \"$KEY\"/,/}/d" "$CONFIG_FILE"
    sed -i "/\"email\": \"$KEY\"/,/}/d" "$CONFIG_FILE"
    # 清理多余的逗号
    sed -i ':a;N;$!ba;s/},\n          }/}\n          }/g' "$CONFIG_FILE"
    # 删除最后一个 client 前的多余逗号（在数组末尾会导致 JSON 无效）
    sed -i ':a;N;$!ba;s/,\n[[:space:]]*\]/\n]/g' "$CONFIG_FILE"
    echo "[OK] 删除成功（使用 sed 方式）"
  }

  update_info
  systemctl restart xray
  echo "[OK] Xray 已重启"
}

# 列出所有用户
list_user() {
  echo "=== 当前用户列表 ==="
  
  # 获取域名和端口
  DOMAIN="$(get_domain)"
  PORT="$(get_port)"
  
  if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
    echo "[ERR] 无法获取域名或端口信息"
    return 1
  fi
  
  if ! grep -q "\"email\":" "$CONFIG_FILE"; then
    echo "（暂无备注用户）"
    return 0
  fi

  python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    domain = '$DOMAIN'
    port = '$PORT'
    
    for i, client in enumerate(config['inbounds'][0]['settings']['clients'], 1):
        email = client.get('email', '(未设置)')
        uuid = client.get('id', '(未知)')
        # 生成配置链接，使用备注作为链接名
        vless_link = f'vless://{uuid}@{domain}:{port}?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni={domain}#{email}'
        
        print(f'{i}. 备注: {email}')
        print(f'   UUID: {uuid}')
        print(f'   链接: {vless_link}')
        print()
except Exception as e:
    # 如果发生任何异常（例如配置文件 JSON 格式错误），
    # 直接退出并返回非零状态，让 shell 走到后面的备用解析分支。
    # 这样可以避免将原始的 Python 错误信息暴露给用户，
    # 并使用 awk/gawk 来尽可能列出已有的数据。
    #
    # 我们不打印 e 的内容，因为它通常包含 JSONDecodeError
    # 报错，这会让用户误以为脚本本身有 bug。
    sys.exit(1)
  " 2>/dev/null || {
    # 如果 python3 不可用，使用 grep/awk
    awk -v domain="$DOMAIN" -v port="$PORT" '
      /"id":/ { 
        id=\$2; 
        gsub(/[",]/, "", id);
        client_id=id;
      }
      /"email":/ { 
        email=\$2; 
        gsub(/[",]/, "", email);
        printf "备注: %s\n", email;
        printf "UUID: %s\n", client_id;
        printf "链接: vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=%s#%s\n\n", client_id, domain, port, domain, email;
      }
    ' "$CONFIG_FILE"
  }
}

# 一键卸载
uninstall() {
  read -p "[WARN]  确认卸载 Xray？此操作不可恢复 [y/N]: " C
  [[ "$C" != "y" ]] && { echo "已取消"; return 0; }

  echo "==> 停止 Xray 服务"
  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  rm -f /etc/systemd/system/xray.service
  systemctl daemon-reload
  
  echo "==> 删除 Xray 文件"
  rm -rf "$XRAY_DIR"
  rm -f "$INFO_FILE"
  
  echo "[OK] 已完全卸载 Xray"
}

# 显示菜单
show_menu() {
  echo
  echo "╔════════════════════════════════════════╗"
  echo "║  Xray 用户管理工具 (xuser.sh)          ║"
  echo "╚════════════════════════════════════════╝"
  echo "1)  添加用户"
  echo "2)  删除用户"
  echo "3)  列出所有用户"
  echo "4)  更新 xray_info.txt"
  echo "5)  一键卸载 Xray"
  echo "0) 退出"
  echo
}

# 主循环
while true; do
  show_menu
  read -p "请选择操作 [0-5]: " CHOICE

  case "$CHOICE" in
    1) add_user ;;
    2) del_user ;;
    3) list_user ;;
    4) update_info && echo "[OK] xray_info.txt 已更新" ;;
    5) uninstall ;;
    0) echo "退出"; exit 0 ;;
    *) echo "[ERR] 无效选项" ;;
  esac
done
EOFXUSER

chmod +x "$XUSER_SCRIPT"
echo "[OK] xuser.sh 已生成: $XUSER_SCRIPT"
echo "[OK] 运行命令：bash $XUSER_SCRIPT 进行用户管理"

# 导出环境变量供 xuser.sh 使用
cat > /root/.xray_env << EOF
export XRAY_DIR="$XRAY_DIR"
export CONFIG_FILE="$XRAY_DIR/config.json"
export INFO_FILE="$INFO_FILE"
EOF

echo "[OK] 环境配置已保存到 /root/.xray_env"
echo ""
echo "[OK] 配置文件已保存: $CONFIG_FILE_PATH"
echo "[OK] 用户信息已保存: $INFO_FILE"
echo ""
echo "初始用户 VLESS 链接: $VLESS_LINK"
