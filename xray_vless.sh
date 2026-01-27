#!/bin/bash
set -e

echo "========== Xray 自动部署脚本 =========="

### 1. 选择 Xray 来源
echo "请选择 Xray 来源："
echo "1) 下载最新官方版本"
echo "2) 使用自定义下载链接"
echo "3) 使用已上传到服务器的压缩文件"
read -p "请输入选项 [1-3]: " SRC

TMP_DIR="/tmp/xray_install"
mkdir -p $TMP_DIR
cd $TMP_DIR

if [ "$SRC" = "1" ]; then
  XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
  curl -L -o xray.zip $XRAY_URL
elif [ "$SRC" = "2" ]; then
  read -p "请输入 Xray 下载链接: " XRAY_URL
  curl -L -o xray.zip $XRAY_URL
elif [ "$SRC" = "3" ]; then
  read -p "请输入 Xray 压缩文件完整路径: " XRAY_ZIP
  cp "$XRAY_ZIP" xray.zip
else
  echo "选项错误"
  exit 1
fi

### 2. 安装位置
read -p "请输入 Xray 安装目录 [默认 /root/xray]: " XRAY_DIR
XRAY_DIR=${XRAY_DIR:-/root/xray}

mkdir -p $XRAY_DIR
unzip -o xray.zip -d $XRAY_DIR
chmod +x $XRAY_DIR/xray

### 3. 生成配置
UUID=$($XRAY_DIR/xray uuid)

read -p "请输入监听端口: " PORT
read -p "请输入域名 (serverName): " DOMAIN
read -p "请输入证书文件路径 (certificateFile): " CERT
read -p "请输入私钥文件路径 (keyFile): " KEY

CONFIG_FILE="$XRAY_DIR/config.json"

cat > $CONFIG_FILE << EOF
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
          "cipherSuites": "TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384",
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

### 4. 创建 systemd 服务
SERVICE_FILE="/etc/systemd/system/xray.service"

cat > $SERVICE_FILE << EOF
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

### 5. 生成 VLESS 链接并保存
VLESS_LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=$DOMAIN#vless-vision"

read -p "请输入链接保存路径 [默认 /root/xray_info.txt]: " SAVE_PATH
SAVE_PATH=${SAVE_PATH:-/root/xray_info.txt}

cat > $SAVE_PATH << EOF
Xray 安装目录: $XRAY_DIR
UUID: $UUID
端口: $PORT
域名: $DOMAIN

VLESS 链接:
$VLESS_LINK
EOF

echo
echo "========== 部署完成 =========="
echo "UUID: $UUID"
echo "VLESS 链接:"
echo "$VLESS_LINK"
echo
echo "已保存到: $SAVE_PATH"
