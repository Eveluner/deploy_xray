#!/bin/bash
set -e

echo "========== Xray VLESS 自动部署脚本 =========="

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
echo "请选择 Xray 安装方式（推荐 26.1.23）："
echo "1) 安装推荐版本 Xray 26.1.23（稳定，已验证）【推荐】"
echo "2) 使用自定义下载链接"
echo "3) 使用已上传到服务器的压缩文件"
read -p "请输入选项 [1-3]: " SRC

TMP_DIR="/tmp/xray_install"
mkdir -p $TMP_DIR
cd $TMP_DIR

if [ "$SRC" = "1" ]; then
  XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v26.1.23/Xray-linux-64.zip"
  echo "==> 下载 Xray 26.1.23"
  curl -L -o xray.zip "$XRAY_URL"
elif [ "$SRC" = "2" ]; then
  read -p "请输入 Xray 下载链接: " XRAY_URL
  curl -L -o xray.zip "$XRAY_URL"
elif [ "$SRC" = "3" ]; then
  read -p "请输入 Xray 压缩文件完整路径: " XRAY_ZIP
  cp "$XRAY_ZIP" xray.zip
else
  echo "[ERR] 选项错误"
  exit 1
fi

### 2. 安装位置
read -p "请输入 Xray 安装目录 [默认 /root/xray]: " XRAY_DIR
XRAY_DIR=${XRAY_DIR:-/root/xray}

mkdir -p "$XRAY_DIR"
unzip -o xray.zip -d "$XRAY_DIR"
chmod +x "$XRAY_DIR/xray"

echo "==> Xray 版本确认"
"$XRAY_DIR/xray" version

### 3. 生成配置（UUID 自动生成）
UUID=$("$XRAY_DIR/xray" uuid)

read -p "请输入监听端口: " PORT
read -p "请输入域名 (serverName): " DOMAIN
read -p "请输入证书文件路径 (certificateFile): " CERT
read -p "请输入私钥文件路径 (keyFile): " KEY

CONFIG_FILE="$XRAY_DIR/config.json"

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
VLESS_LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=$DOMAIN#vless-vision"

read -p "请输入链接保存路径 [默认 /root/xray_info.txt]: " SAVE_PATH
SAVE_PATH=${SAVE_PATH:-/root/xray_info.txt}

cat > "$SAVE_PATH" << EOF
Xray 安装目录: $XRAY_DIR
Xray 版本: 26.1.23
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
echo "已保存到: $SAVE_PATH"

### 7. 生成 xuser.sh（用户管理脚本）
read -p "请输入 xuser.sh 保存路径 [默认 /root/xuser.sh]: " XUSER_PATH
XUSER_PATH=${XUSER_PATH:-/root/xuser.sh}

cat > "$XUSER_PATH" << 'EOFXUSER'
#!/bin/bash
set -e

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

  cat > "$INFO_FILE" << EOF
Xray 安装目录: $XRAY_DIR
Xray 版本: 26.1.23
域名: $DOMAIN
端口: $PORT

VLESS 连接信息:
================

EOF

  # 从配置中提取用户信息
  awk '
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
        printf "VLESS 链接: vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=%s\n\n", client_id, ENVIRON["DOMAIN"], ENVIRON["PORT"], ENVIRON["DOMAIN"];
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
    echo "[OK] 删除成功（使用 sed 方式）"
  }

  update_info
  systemctl restart xray
  echo "[OK] Xray 已重启"
}

# 列出所有用户
list_user() {
  echo "=== 当前用户列表 ==="
  if ! grep -q "\"email\":" "$CONFIG_FILE"; then
    echo "（暂无备注用户）"
    return 0
  fi

  python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    for i, client in enumerate(config['inbounds'][0]['settings']['clients'], 1):
        email = client.get('email', '(未设置)')
        uuid = client.get('id', '(未知)')
        print(f'{i}. 备注: {email}')
        print(f'   UUID: {uuid}')
        print()
except Exception as e:
    print(f'错误: {e}')
  " 2>/dev/null || {
    # 如果 python3 不可用，使用 grep/awk
    awk '
      /"id":/ { 
        id=\$2; 
        gsub(/[",]/, "", id);
        printf "   UUID: %s\n", id;
      }
      /"email":/ { 
        email=\$2; 
        gsub(/[",]/, "", email);
        printf "备注: %s\n", email;
        printf "\n"
      }
    ' "$CONFIG_FILE"
  }
}

# 一键卸载
uninstall() {
  read -p "[WARN] 确认卸载 Xray？此操作不可恢复 [y/N]: " C
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

chmod +x "$XUSER_PATH"
echo "==> xuser.sh 已生成: $XUSER_PATH"
echo "==> 运行命令：bash $XUSER_PATH 进行用户管理"

# 导出环境变量供 xuser.sh 使用
cat > /root/.xray_env << EOF
export XRAY_DIR="$XRAY_DIR"
export CONFIG_FILE="$CONFIG_FILE"
export INFO_FILE="$SAVE_PATH"
EOF

echo "[OK] 环境配置已保存到 /root/.xray_env"
