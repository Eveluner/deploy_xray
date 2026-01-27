#!/bin/bash
set -e

echo "========== Xray 自动部署（含用户管理脚本） =========="

### 0. 依赖检测
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

for p in curl unzip; do
  command -v $p >/dev/null 2>&1 || install_pkg $p
done

### 1. Xray 版本固定 26.1.23（推荐）
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v26.1.23/Xray-linux-64.zip"

read -p "Xray 安装目录 [默认 /root/xray]: " XRAY_DIR
XRAY_DIR=${XRAY_DIR:-/root/xray}

mkdir -p /tmp/xray && cd /tmp/xray
curl -L -o xray.zip "$XRAY_URL"
unzip -o xray.zip -d "$XRAY_DIR"
chmod +x "$XRAY_DIR/xray"

echo "==> Xray 版本："
"$XRAY_DIR/xray" version

### 2. 生成初始配置
UUID=$("$XRAY_DIR/xray" uuid)

read -p "监听端口: " PORT
read -p "域名: " DOMAIN
read -p "证书路径: " CERT
read -p "私钥路径: " KEY

CONFIG="$XRAY_DIR/config.json"

cat > "$CONFIG" << EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vless-vision",
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "flow": "xtls-rprx-vision", "email": "default" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$DOMAIN",
          "certificates": [
            { "certificateFile": "$CERT", "keyFile": "$KEY" }
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
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

### 3. 配置校验
"$XRAY_DIR/xray" run -test -config "$CONFIG"

### 4. systemd 服务
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
ExecStart=$XRAY_DIR/xray run -config $CONFIG
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

### 5. 生成 xray_info.txt（保存路径可选）
read -p "xray_info.txt 保存路径 [默认 /root/xray_info.txt]: " INFO
INFO=${INFO:-/root/xray_info.txt}

cat > "$INFO" << EOF
DOMAIN=$DOMAIN
PORT=$PORT
EOF

### 6. 生成 xuesr.sh（保存路径可选）
read -p "xuesr.sh 保存路径 [默认 /root/xuesr.sh]: " XUESR
XUESR=${XUESR:-/root/xuesr.sh}

cat > "$XUESR" << 'EOF'
#!/bin/bash

XRAY_DIR="/root/xray"
CONFIG="$XRAY_DIR/config.json"
BIN="$XRAY_DIR/xray"
INFO="/root/xray_info.txt"

get_domain() { grep "^DOMAIN=" "$INFO" | cut -d= -f2; }
get_port()   { grep "^PORT=" "$INFO" | cut -d= -f2; }

add_user() {
  read -p "请输入用户备注名（如 alice-iphone）: " REMARK
  if [ -z "$REMARK" ]; then
    echo "备注不能为空"
    return
  fi

  if grep -q "\"email\": \"$REMARK\"" "$CONFIG"; then
    echo "备注已存在"
    return
  fi

  UUID=$($BIN uuid)

  sed -i "/\"clients\": \[/a\          { \"id\": \"$UUID\", \"flow\": \"xtls-rprx-vision\", \"email\": \"$REMARK\" }," "$CONFIG"

  echo "✅ 已添加用户"
  echo "备注: $REMARK"
  echo "UUID: $UUID"

  update_info
  systemctl reload xray || systemctl restart xray
}

del_user() {
  read -p "请输入要删除的 备注名 或 UUID: " KEY
  if [ -z "$KEY" ]; then return; fi

  sed -i "/$KEY/d" "$CONFIG"

  update_info
  systemctl reload xray || systemctl restart xray
  echo "✅ 已删除: $KEY"
}

list_user() {
  echo "当前用户列表："
  awk '
    /"id":/ {
      uuid=$4
    }
    /"email":/ {
      remark=$4
      gsub(/"/,"",remark)
      print "备注:",remark," UUID:",uuid
    }
  ' "$CONFIG"
}

update_info() {
  DOMAIN=$(get_domain)
  PORT=$(get_port)

  echo "Xray 用户列表：" > "$INFO"
  echo "DOMAIN=$DOMAIN" >> "$INFO"
  echo "PORT=$PORT" >> "$INFO"
  echo "------------------------" >> "$INFO"

  awk -v d="$DOMAIN" -v p="$PORT" '
    /"id":/ {
      uuid=$4
      gsub(/"/,"",uuid)
    }
    /"email":/ {
      remark=$4
      gsub(/"/,"",remark)
      print remark ":"
      print "vless://" uuid "@" d ":" p "?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=" d
      print ""
    }
  ' "$CONFIG" >> "$INFO"
}

uninstall() {
  read -p "确认卸载 Xray？[y/N]: " C
  [[ "$C" != "y" ]] && return

  systemctl stop xray
  systemctl disable xray
  rm -f /etc/systemd/system/xray.service
  rm -rf "$XRAY_DIR"
  rm -f "$INFO"
  echo "🗑️ Xray 已完全卸载"
}

echo
echo "===== Xray 用户管理 ====="
echo "1) 新增用户（带备注）"
echo "2) 删除用户（备注 / UUID）"
echo "3) 列出用户"
echo "4) 卸载 Xray"
read -p "请选择: " C

case $C in
  1) add_user ;;
  2) del_user ;;
  3) list_user ;;
  4) uninstall ;;
  *) echo "无效选项" ;;
esac
EOF

chmod +x "$XUESR"

echo
echo "========== 部署完成 =========="
echo "Xray 安装目录: $XRAY_DIR"
echo "xray_info.txt: $INFO"
echo "用户管理脚本: $XUESR"
echo "运行：$XUESR 进行用户管理"
