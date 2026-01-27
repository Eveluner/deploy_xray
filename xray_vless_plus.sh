#!/bin/bash
set -e

echo "========== Xray 自动部署脚本 =========="

### 0. 环境 & 依赖检查
echo "==> 检测运行环境"

if ! command -v systemctl >/dev/null 2>&1; then
  echo "❌ 当前系统不支持 systemd"
  exit 1
fi

install_pkg() {
  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$@"
  else
    echo "❌ 不支持的包管理器"
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
  echo "❌ 选项错误"
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
            "flow": "xtls-rprx-vision"
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
UUID: $UUID
端口: $PORT
域名: $DOMAIN

VLESS 链接:
$VLESS_LINK
EOF

echo
echo "========== 部署完成 =========="
echo "$VLESS_LINK"
echo "已保存到: $SAVE_PATH"

### 7. 生成 xuser.sh（不影响主脚本逻辑）
read -p "请输入 xuser.sh 保存路径 [默认 /root/xuser.sh]: " XUSER_PATH
XUSER_PATH=${XUSER_PATH:-/root/xuser.sh}

cat > "$XUSER_PATH" << 'EOF'
#!/bin/bash
set -e

# ==========================
# Xray 用户管理脚本 xuser.sh
# ==========================

XRAY_DIR="${XRAY_DIR:-/root/xray}"
CONFIG_FILE="${CONFIG_FILE:-$XRAY_DIR/config.json}"
BIN="${BIN:-$XRAY_DIR/xray}"
INFO_FILE="${SAVE_PATH:-/root/xray_info.txt}"

# 获取 domain / port
get_domain() { grep -E "^域名:" "$INFO_FILE" | awk -F": " '{print $2}'; }
get_port() { grep -E "^端口:" "$INFO_FILE" | awk -F": " '{print $2}'; }

# 更新 xray_info.txt
update_info() {
  DOMAIN="$(get_domain)"
  PORT="$(get_port)"

  echo "Xray 安装目录: $XRAY_DIR" > "$INFO_FILE"
  echo "Xray 版本: 26.1.23" >> "$INFO_FILE"
  echo "域名: $DOMAIN" >> "$INFO_FILE"
  echo "端口: $PORT" >> "$INFO_FILE"
  echo "" >> "$INFO_FILE"
  echo "用户列表:" >> "$INFO_FILE"
  echo "" >> "$INFO_FILE"

  # 解析配置中的 UUID + email
  awk '
    /"id":/ { uuid=$2; gsub(/[",]/,"",uuid) }
    /"email":/ { email=$2; gsub(/[",]/,"",email);
      print "备注: " email;
      print "vless://" uuid "@" ENVIRON["DOMAIN"] ":" ENVIRON["PORT"] "?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=" ENVIRON["DOMAIN"];
      print ""
    }
  ' DOMAIN="$DOMAIN" PORT="$PORT" "$CONFIG_FILE" >> "$INFO_FILE"
}

# 添加用户
add_user() {
  read -p "请输入用户备注（例如: alice-iphone）: " REMARK
  if [ -z "$REMARK" ]; then
    echo "备注不能为空"
    exit 1
  fi

  # 生成 UUID
  UUID="$($BIN uuid)"

  # 插入到 clients 数组中
  sed -i "/\"clients\": \[/a\          { \"id\": \"$UUID\", \"flow\": \"xtls-rprx-vision\", \"email\": \"$REMARK\" }," "$CONFIG_FILE"

  echo "✅ 添加成功"
  echo "备注: $REMARK"
  echo "UUID: $UUID"

  update_info
  systemctl restart xray
}

# 删除用户（按 UUID 或备注）
del_user() {
  read -p "请输入要删除的 UUID 或备注: " KEY
  if [ -z "$KEY" ]; then
    echo "取消"
    exit 0
  fi

  sed -i "/$KEY/d" "$CONFIG_FILE"
  echo "✅ 删除成功: $KEY"

  update_info
  systemctl restart xray
}

# 列出用户
list_user() {
  echo "当前用户列表："
  awk '
    /"id":/ { uuid=$2; gsub(/[",]/,"",uuid) }
    /"email":/ { email=$2; gsub(/[",]/,"",email);
      print "备注:" email "  UUID:" uuid
    }
  ' "$CONFIG_FILE"
}

# 卸载
uninstall() {
  read -p "确认卸载 Xray？[y/N]: " C
  [[ "$C" != "y" ]] && exit 0

  systemctl stop xray
  systemctl disable xray
  rm -f /etc/systemd/system/xray.service
  rm -rf "$XRAY_DIR"
  rm -f "$INFO_FILE"
  echo "✅ 已卸载"
}

echo "====== xuser.sh (Xray 用户管理) ======"
echo "1) 添加用户"
echo "2) 删除用户"
echo "3) 列出用户"
echo "4) 卸载 Xray"
read -p "请选择 [1-4]: " CHOICE

case "$CHOICE" in
  1) add_user ;;
  2) del_user ;;
  3) list_user ;;
  4) uninstall ;;
  *) echo "无效选项" ;;
esac
EOF

chmod +x "$XUSER_PATH"

echo "==> xuser.sh 已生成: $XUSER_PATH"
echo "==> 运行：$XUSER_PATH 进行用户管理"
