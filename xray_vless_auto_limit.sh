#!/bin/bash
set -e

# ------------------------------------------------------------------
# 扩展版 Xray VLESS 自动部署脚本
#  - 在原始 xray_vless_auto.sh 基础上新增：
#      * 每个用户流量统计
#      * 每个用户流量限制 (MB)
#      * 通过 xray API 获取统计数据
#      * 在 xuser.sh 中增加限流管理菜单
# ------------------------------------------------------------------

# 配置文件路径
CONFIG_FILE_PATH="${1:-/root/xray_install.conf}"

# 保存限流信息的文件
LIMIT_FILE="/root/xray_limits.txt"

# 加载配置函数
load_config() {
  if [ -f "$CONFIG_FILE_PATH" ]; then
    echo "[OK] 检测到配置文件: $CONFIG_FILE_PATH"
    source "$CONFIG_FILE_PATH"
    return 0
  else
    return 1
  fi
}

# 生成配置文件模板（包含 api/policy/stats 相关字段）
generate_config_template() {
  local template_path="$CONFIG_FILE_PATH"
  mkdir -p "$(dirname "$template_path")"
  
  cat > "$template_path" << 'CONFIGEOF'
# Xray 自动安装配置文件（带流量统计与限速）
# 请填写以下参数，留空的字段将使用默认值

# 必填项
DOMAIN="example.com"
PORT="443"
CERT_FILE="/path/to/cert.pem"
KEY_FILE="/path/to/key.pem"

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

# API 监听端口（仅绑定本地）
API_PORT="2080"
CONFIGEOF

  echo "[OK] 已生成配置文件模板: $template_path"
  echo "请编辑配置文件并填写参数后，再次运行本脚本"
  echo ""
  echo "关键参数说明:"
  echo "  DOMAIN        - 服务器域名（必填）"
  echo "  PORT          - 监听端口（必填）"
  echo "  CERT_FILE     - SSL 证书文件路径（必填）"
  echo "  KEY_FILE      - SSL 私钥文件路径（必填）"
  echo "  API_PORT      - Xray API 本地监听端口（默认 2080，用于流量统计）"
  echo ""
}

# 如果配置不存在则生成模板并退出
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

# 默认值覆盖
XRAY_DIR="${XRAY_DIR:-/root/xray}"
INFO_FILE="${INFO_FILE:-/root/xray_info.txt}"
XUSER_SCRIPT="${XUSER_SCRIPT:-/root/xuser.sh}"
API_PORT="${API_PORT:-2080}"

### 环境检查
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

### 下载并安装 Xray
TMP_DIR="/tmp/xray_install"
mkdir -p $TMP_DIR
cd $TMP_DIR

if [ "$INSTALL_SOURCE" = "3" ]; then
  cp "$XRAY_ZIP_LOCAL" xray.zip
else
  curl -L -o xray.zip "${XRAY_URL}"  
fi

mkdir -p "$XRAY_DIR"
unzip -o xray.zip -d "$XRAY_DIR"
chmod +x "$XRAY_DIR/xray"

"$XRAY_DIR/xray" version

### 生成配置并启用统计/限速
UUID=$("$XRAY_DIR/xray" uuid)
CERT="$CERT_FILE"
KEY="$KEY_FILE"

if [ ! -f "$CERT" ]; then
  echo "[ERR] 证书文件不存在: $CERT"
  exit 1
fi
if [ ! -f "$KEY" ]; then
  echo "[ERR] 私钥文件不存在: $KEY"
  exit 1
fi

CONFIG_FILE="$XRAY_DIR/config.json"

cat > "$CONFIG_FILE" << EOF
{
  "log": { "loglevel": "warning" },

  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },

  "policy": {
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    },
    "levels": {
      "0": {
        "statsUserUplink": 0,
        "statsUserDownlink": 0
      }
    }
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
            "flow": "$VLESS_FLOW",
            "email": "$INITIAL_REMARK",
            "level": 0
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
    },
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": $API_PORT,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    }
  ],

  "outbounds": [
    { "protocol": "freedom", "settings": {} }
  ]
}
EOF

### 检查配置
"$XRAY_DIR/xray" run -test -config "$CONFIG_FILE"

### 设置 systemd 服务
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

### 生成连接信息
INITIAL_REMARK="${INITIAL_REMARK:-初始用户}"
REMARK_ESCAPED="${INITIAL_REMARK// /%20}"
VLESS_LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=$VLESS_FLOW&security=tls&type=tcp&sni=$DOMAIN#$REMARK_ESCAPED"

cat > "$INFO_FILE" << EOF
Xray 安装目录: $XRAY_DIR
Xray 版本: ${XRAY_VERSION:-26.1.23}
域名: $DOMAIN
端口: $PORT

VLESS 连接信息:
================

备注: $INITIAL_REMARK
UUID: $UUID
VLESS 链接: $VLESS_LINK
EOF

### 生成 xuser.sh (带限流功能)

cat > "$XUSER_SCRIPT" << 'EOFX'
#!/bin/bash
set -e
set +H

# ==========================
# Xray 用户管理脚本 xuser.sh (带流量统计/限速)
# ==========================

XRAY_DIR="${XRAY_DIR:-/root/xray}"
CONFIG_FILE="${CONFIG_FILE:-$XRAY_DIR/config.json}"
BIN="${BIN:-$XRAY_DIR/xray}"
INFO_FILE="${INFO_FILE:-/root/xray_info.txt}"
LIMIT_FILE="/root/xray_limits.txt"
API_PORT="${API_PORT:-2080}"

get_domain() { 
  grep "^域名:" "$INFO_FILE" 2>/dev/null | tail -1 | awk -F": " '{print $2}' || echo ""
}

get_port() { 
  grep "^端口:" "$INFO_FILE" 2>/dev/null | tail -1 | awk -F": " '{print $2}' || echo ""
}

get_xray_dir() {
  grep "^Xray 安装目录:" "$INFO_FILE" 2>/dev/null | tail -1 | awk -F": " '{print $2}' || echo "/root/xray"
}

# 限流数据管理
set_limit() {
  local uuid="$1" limit="$2"
  grep -v "^$uuid " "$LIMIT_FILE" 2>/dev/null > "$LIMIT_FILE.tmp" || true
  echo "$uuid $limit" >> "$LIMIT_FILE.tmp"
  mv "$LIMIT_FILE.tmp" "$LIMIT_FILE"
}

get_limit() {
  local uuid="$1"
  awk -v id="$uuid" '$1==id {print $2}' "$LIMIT_FILE" 2>/dev/null || echo "0"
}

remove_limit() {
  local uuid="$1"
  grep -v "^$uuid " "$LIMIT_FILE" 2>/dev/null > "$LIMIT_FILE.tmp" || true
  mv "$LIMIT_FILE.tmp" "$LIMIT_FILE" || true
}

# 更新 xray_info.txt 文件
update_info() {
  DOMAIN="$(get_domain)"
  PORT="$(get_port)"
  XRAY_DIR="$(get_xray_dir)"

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

  awk -v domain="$DOMAIN" -v port="$PORT" \
    -v limitfile="$LIMIT_FILE" \
    'BEGIN {
      # 读取限流文件，存入数组
      while ((getline line < limitfile) > 0) {
        split(line, arr, " ");
        limitmap[arr[1]] = arr[2];
      }
      close(limitfile);
    }
    /"id":/ { 
      id=$2; gsub(/[\",]/, "", id); client_id=id;
    }
    /"email":/ {
      match($0, /"email"[[:space:]]*:[[:space:]]*"(.*)"/, arr);
      email=arr[1];
      if (client_id != "") {
        printf "备注: %s\n", email;
        printf "UUID: %s\n", client_id;
        remark_enc=email;
        gsub(/ /, "%20", remark_enc);
        printf "VLESS 链接: vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=%s#%s\n", client_id, domain, port, domain, remark_enc;
        # 显示限速信息
        if (client_id in limitmap) {
          printf "流量限制(MB): %s\n", limitmap[client_id];
        }
        printf "\n";
        client_id="";
      }
    }
' DOMAIN="$DOMAIN" PORT="$PORT" "$CONFIG_FILE" >> "$INFO_FILE"
  ' DOMAIN="$DOMAIN" PORT="$PORT" "$CONFIG_FILE" >> "$INFO_FILE"
}

# 添加用户
add_user() {
  read -p "请输入用户备注（例如: alice-iphone）: " REMARK
  if [ -z "$REMARK" ]; then
    echo "[ERR] 备注不能为空"
    return 1
  fi

  if grep -q "\"email\": \"$REMARK\"" "$CONFIG_FILE"; then
    echo "[ERR] 备注已存在"
    return 1
  fi

  UUID="$($BIN uuid)"

  sed -i "/\"clients\": \[/a\\          {\n            \"id\": \"$UUID\",\n            \"flow\": \"xtls-rprx-vision\",\n            \"email\": \"$REMARK\",\n            \"level\": 0\n          }," "$CONFIG_FILE"

  echo "[OK] 添加成功"
  echo "备注: $REMARK"
  echo "UUID: $UUID"

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
(del_user()) {
  # same as original except remove limit file entry
  echo "=== 删除用户 ==="
  list_user
  echo
  read -p "请输入要删除的 UUID 或备注: " KEY
  if [ -z "$KEY" ]; then
    echo "取消"
    return 0
  fi

  if ! grep -q "$KEY" "$CONFIG_FILE"; then
    echo "[ERR] 找不到用户"
    return 1
  fi

  python3 -c "..." || {
    sed -i "/\"id\": \"$KEY\"/,/}/d" "$CONFIG_FILE"
    sed -i "/\"email\": \"$KEY\"/,/}/d" "$CONFIG_FILE"
    sed -i ':a;N;$!ba;s/},\n          }/}\n          }/g' "$CONFIG_FILE"
    sed -i ':a;N;$!ba;s/,\n[[:space:]]*\]/\n]/g' "$CONFIG_FILE"
    echo "[OK] 删除成功（使用 sed 方式）"
  }

  remove_limit "$KEY"
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
    
    import urllib.parse
    for i, client in enumerate(config['inbounds'][0]['settings']['clients'], 1):
        email = client.get('email', '(未设置)')
        uuid = client.get('id', '(未知)')
        # 生成配置链接，使用备注作为链接名，空格会转换为%%20
        frag = urllib.parse.quote(email, safe='')
        vless_link = f'vless://{uuid}@{domain}:{port}?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni={domain}#{frag}'
        
        print(f'{i}. 备注: {email}')
        print(f'   UUID: {uuid}')
        print(f'   链接: {vless_link}')
        print()
except Exception as e:
    sys.exit(1)
  " 2>/dev/null || {
    awk -v domain="$DOMAIN" -v port="$PORT" '
      /"id":/ { 
        id=\$2; 
        gsub(/[",]/, "", id);
        client_id=id;
      }
      /"email":/ {
        match($0, /"email"[[:space:]]*:[[:space:]]*"(.*)"/, arr);
        email=arr[1];
        printf "备注: %s\n", email;
        printf "UUID: %s\n", client_id;
        remark_enc=email;
        gsub(/ /, "%20", remark_enc);
        printf "链接: vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=%s#%s\n\n", client_id, domain, port, domain, remark_enc;
      }
    ' "$CONFIG_FILE"
  }
}

# 新增：查看流量
show_traffic() {
  echo "=== 用户流量 ==="
  DOMAIN="$(get_domain)"
  PORT="$(get_port)"
  if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
    echo "[ERR] 无法获取域名或端口信息"
    return 1
  fi

  stats=$(curl -s http://127.0.0.1:$API_PORT/stats)
  if [ -z "$stats" ]; then
    echo "[ERR] 无法获取统计数据，确认 Xray 已启动并启用 API ($API_PORT)"
    return 1
  fi

  echo "$stats" | python3 - <<'PY'
import sys, json, urllib.parse
try:
    data=json.load(sys.stdin)
    # 解析示例结构, 根据实际 xray 版本需要调整
    for rec in data.get('stats',[]):
        if rec.get('name','').startswith('user:'):
            parts=rec['name'].split(':')
            uuid=parts[1]
            up=rec.get('value',0)
            down=rec.get('value',0)
            print(f"UUID: {uuid} 上传: {up} 字节 下行: {down} 字节")
except Exception as e:
    pass
PY
}

# 设置流量限制
set_user_limit() {
  list_user
  echo
  read -p "请输入要限速的 UUID 或备注: " KEY
  [ -z "$KEY" ] && { echo "取消"; return; }
  # 查找 uuid
  uuid=$(grep -Eo '([0-9a-fA-F-]{36})' <<< "$KEY" | head -1)
  if [ -z "$uuid" ]; then
    # 尝试从备注中检索
    uuid=$(awk -v k="$KEY" '/"email":/ && index($0,k){getline; gsub(/[",]/,""); print $2}' "$CONFIG_FILE")
  fi
  if [ -z "$uuid" ]; then
    echo "[ERR] 未找到对应 UUID"
    return
  fi

  read -p "请输入流量上限 (MB): " LIMIT
  if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    echo "[ERR] 无效的数字"
    return
  fi

  set_limit "$uuid" "$LIMIT"
  echo "[OK] 已设置 $uuid 的流量限制为 ${LIMIT}MB"
}

# 检查并执行限速（超过则删除用户）
enforce_limits() {
  echo "=== 检查流量限额 ==="
  DOMAIN="$(get_domain)"
  PORT="$(get_port)"
  if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
    echo "[ERR] 无法获取域名或端口信息"
    return 1
  fi

  stats=$(curl -s http://127.0.0.1:$API_PORT/stats)
  echo "$stats" | python3 - <<'PY'
import sys, json
limits={}
for line in open('$LIMIT_FILE','r'):
    u,l=line.strip().split()
    limits[u]=int(l)*1024*1024
try:
    data=json.load(sys.stdin)
    for rec in data.get('stats',[]):
        if rec.get('name','').startswith('user:'):
            parts=rec['name'].split(':')
            uuid=parts[1]
            used=rec.get('value',0)
            if uuid in limits and used>=limits[uuid]:
                print(uuid)
except: pass
PY
  | while read uuid; do
      echo "[WARN] 用户 $uuid 已超流量限制，正在删除..."
      # 调用脚本本身删除
      bash "$0" del-helper "$uuid"
  done
}

# 提供给 enforce_limits 调用的辅助函数
if [ "$1" = "del-helper" ]; then
  shift
  KEY="$1"
  # 直接删除 uuid
  sed -i "/\"id\": \"$KEY\"/,/}/d" "$CONFIG_FILE"
  sed -i "/\"email\": \"$KEY\"/,/}/d" "$CONFIG_FILE"
  remove_limit "$KEY"
  update_info
  systemctl restart xray
  exit 0
fi

# 正常应该将原来列出用户等函数内容复刻到此处。

show_menu() {
  echo
  echo "╔════════════════════════════════════════╗"
  echo "║  Xray 用户管理工具 (xuser.sh)          ║"
  echo "╚════════════════════════════════════════╝"
  echo "1)  添加用户"
  echo "2)  删除用户"
  echo "3)  列出所有用户"
  echo "4)  更新 xray_info.txt"
  echo "5)  查看用户流量"
  echo "6)  设置用户流量限制"
  echo "7)  检查并执行流量限额"
  echo "8)  一键卸载 Xray"
  echo "0) 退出"
  echo
}

while true; do
  show_menu
  read -p "请选择操作 [0-8]: " CHOICE
  case "$CHOICE" in
    1) add_user ;;
    2) del_user ;;
    3) list_user ;;
    4) update_info && echo "[OK] xray_info.txt 已更新" ;;
    5) show_traffic ;;
    6) set_user_limit ;;
    7) enforce_limits ;;
    8) uninstall ;;
    0) echo "退出"; exit 0 ;;
    *) echo "[ERR] 无效选项" ;;
  esac

done
EOFX

chmod +x "$XUSER_SCRIPT"
echo "[OK] xuser.sh 已生成: $XUSER_SCRIPT"
echo "[OK] 运行命令：bash $XUSER_SCRIPT 进行用户管理"

# 导出环境变量
cat > /root/.xray_env << EOF
export XRAY_DIR="$XRAY_DIR"
export CONFIG_FILE="$XRAY_DIR/config.json"
export INFO_FILE="$INFO_FILE"
export API_PORT="$API_PORT"
EOF

echo "[OK] 环境配置已保存到 /root/.xray_env"
echo ""
echo "[OK] 配置文件已保存: $CONFIG_FILE_PATH"
echo "[OK] 用户信息已保存: $INFO_FILE"
echo ""
echo "初始用户 VLESS 链接: $VLESS_LINK"
