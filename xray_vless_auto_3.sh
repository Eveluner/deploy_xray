#!/bin/bash
set -Eeuo pipefail
set +H

DEFAULT_CONFIG_FILE="/root/xray_install.conf"
DEFAULT_XRAY_VERSION="26.1.23"
DEFAULT_VLESS_FLOW="xtls-rprx-vision"
DEFAULT_SERVICE_NAME="xray"

CONFIG_FILE_PATH="${1:-$DEFAULT_CONFIG_FILE}"
TMP_DIR=""

cleanup() {
  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

die() {
  echo "[ERR] $*" >&2
  exit 1
}

ok() {
  echo "[OK] $*"
}

log() {
  echo "==> $*"
}

ensure_parent_dir() {
  local path="$1"
  local dir
  dir="$(dirname "$path")"
  mkdir -p "$dir"
}

backup_file() {
  local file="$1"
  local backup

  [ -f "$file" ] || return 0
  backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "$file" "$backup"
  ok "已备份: $backup"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 用户运行此脚本"
  fi
}

load_config() {
  if [ -f "$CONFIG_FILE_PATH" ]; then
    ok "检测到配置文件: $CONFIG_FILE_PATH"
    # 配置文件采用 shell 变量格式，只从可信路径加载。
    # shellcheck source=/dev/null
    source "$CONFIG_FILE_PATH"
    return 0
  fi

  return 1
}

generate_config_template() {
  local template_path="$CONFIG_FILE_PATH"

  ensure_parent_dir "$template_path"
  cat > "$template_path" << 'CONFIGEOF'
# Xray 自动安装配置文件
# 配置文件采用 shell 变量格式，请只保存到可信路径。

# 必填项
DOMAIN="example.com"
PORT="443"
CERT_FILE="/path/to/cert.pem"
KEY_FILE="/path/to/key.pem"

# 可选项
XRAY_DIR="/root/xray"
XRAY_VERSION="26.1.23"
XRAY_ARCH="auto"
VLESS_FLOW="xtls-rprx-vision"
INITIAL_REMARK="初始用户"

# 下载方式：1=按版本从 GitHub 下载, 2=自定义 URL, 3=本地 zip 文件
INSTALL_SOURCE="1"
XRAY_URL=""
XRAY_ZIP_LOCAL=""

# 文件保存路径
INFO_FILE="/root/xray_info.txt"
XUSER_SCRIPT="/root/xuser.sh"
XRAY_ENV_FILE="/root/.xray_env"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="xray"
CONFIGEOF

  ok "已生成配置文件模板: $template_path"
  echo "请编辑配置文件并填写参数后，再次运行本脚本"
  echo
  echo "关键参数说明:"
  echo "  DOMAIN        - 服务器域名（必填，不能保留 example.com）"
  echo "  PORT          - 监听端口（必填，1-65535）"
  echo "  CERT_FILE     - SSL 证书文件路径（必填）"
  echo "  KEY_FILE      - SSL 私钥文件路径（必填）"
  echo "  XRAY_ARCH     - auto/64/arm64-v8a/arm32-v7a 等 release 架构名"
  echo
}

normalize_config() {
  DOMAIN="${DOMAIN:-}"
  PORT="${PORT:-}"
  CERT_FILE="${CERT_FILE:-}"
  KEY_FILE="${KEY_FILE:-}"

  XRAY_DIR="${XRAY_DIR:-/root/xray}"
  XRAY_VERSION="${XRAY_VERSION:-$DEFAULT_XRAY_VERSION}"
  XRAY_VERSION="${XRAY_VERSION#v}"
  XRAY_ARCH="${XRAY_ARCH:-auto}"
  VLESS_FLOW="${VLESS_FLOW:-$DEFAULT_VLESS_FLOW}"
  INITIAL_REMARK="${INITIAL_REMARK:-初始用户}"

  INSTALL_SOURCE="${INSTALL_SOURCE:-1}"
  XRAY_URL="${XRAY_URL:-}"
  XRAY_ZIP_LOCAL="${XRAY_ZIP_LOCAL:-}"

  INFO_FILE="${INFO_FILE:-/root/xray_info.txt}"
  XUSER_SCRIPT="${XUSER_SCRIPT:-/root/xuser.sh}"
  XRAY_ENV_FILE="${XRAY_ENV_FILE:-/root/.xray_env}"
  SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
  SYSTEMD_DIR="${SYSTEMD_DIR%/}"
  SERVICE_NAME="${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}"

  CONFIG_FILE="$XRAY_DIR/config.json"
  XRAY_BIN="$XRAY_DIR/xray"
  SERVICE_FILE="$SYSTEMD_DIR/${SERVICE_NAME}.service"
}

contains_newline() {
  local value="$1"
  [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]
}

validate_path_value() {
  local name="$1"
  local value="$2"

  [ -n "$value" ] || die "$name 不能为空"
  if contains_newline "$value"; then
    die "$name 不能包含换行符"
  fi
}

validate_xray_dir() {
  validate_path_value "XRAY_DIR" "$XRAY_DIR"

  case "$XRAY_DIR" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      die "XRAY_DIR 指向高风险系统目录: $XRAY_DIR"
      ;;
  esac
}

validate_config() {
  [ -n "$DOMAIN" ] || die "配置文件中缺少 DOMAIN"
  [ "$DOMAIN" != "example.com" ] || die "请先把 DOMAIN 从 example.com 改为真实域名"
  [ -n "$PORT" ] || die "配置文件中缺少 PORT"
  [ -n "$CERT_FILE" ] || die "配置文件中缺少 CERT_FILE"
  [ -n "$KEY_FILE" ] || die "配置文件中缺少 KEY_FILE"

  if contains_newline "$DOMAIN"; then
    die "DOMAIN 不能包含换行符"
  fi
  if [[ "$DOMAIN" =~ [[:space:]] ]]; then
    die "DOMAIN 不能包含空白字符"
  fi
  if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    die "PORT 必须是 1-65535 之间的数字"
  fi
  if ! [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    die "SERVICE_NAME 只能包含字母、数字、点、下划线、@ 和连字符"
  fi

  validate_xray_dir
  validate_path_value "CERT_FILE" "$CERT_FILE"
  validate_path_value "KEY_FILE" "$KEY_FILE"
  validate_path_value "INFO_FILE" "$INFO_FILE"
  validate_path_value "XUSER_SCRIPT" "$XUSER_SCRIPT"
  validate_path_value "XRAY_ENV_FILE" "$XRAY_ENV_FILE"
  validate_path_value "SYSTEMD_DIR" "$SYSTEMD_DIR"

  [ -f "$CERT_FILE" ] || die "证书文件不存在: $CERT_FILE"
  [ -r "$CERT_FILE" ] || die "证书文件不可读: $CERT_FILE"
  [ -f "$KEY_FILE" ] || die "私钥文件不存在: $KEY_FILE"
  [ -r "$KEY_FILE" ] || die "私钥文件不可读: $KEY_FILE"

  case "$INSTALL_SOURCE" in
    1) ;;
    2)
      [ -n "$XRAY_URL" ] || die "INSTALL_SOURCE=2 时必须填写 XRAY_URL"
      ;;
    3)
      [ -n "$XRAY_ZIP_LOCAL" ] || die "INSTALL_SOURCE=3 时必须填写 XRAY_ZIP_LOCAL"
      [ -f "$XRAY_ZIP_LOCAL" ] || die "本地压缩文件不存在: $XRAY_ZIP_LOCAL"
      [ -r "$XRAY_ZIP_LOCAL" ] || die "本地压缩文件不可读: $XRAY_ZIP_LOCAL"
      ;;
    *)
      die "INSTALL_SOURCE 只能是 1、2 或 3"
      ;;
  esac
}

install_pkg() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y "$@"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$@"
  else
    die "不支持的包管理器，请手动安装依赖: $*"
  fi
}

ensure_dependencies() {
  local missing=()
  local pkg

  if ! command -v systemctl >/dev/null 2>&1; then
    die "当前系统不支持 systemd"
  fi

  for pkg in curl unzip python3; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    log "安装依赖: ${missing[*]}"
    install_pkg "${missing[@]}"
  fi
}

detect_xray_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "64"
      ;;
    aarch64|arm64)
      echo "arm64-v8a"
      ;;
    armv7l|armv7*)
      echo "arm32-v7a"
      ;;
    armv6l|armv6*)
      echo "arm32-v6"
      ;;
    i386|i686)
      echo "32"
      ;;
    *)
      die "无法自动识别架构，请在配置文件中设置 XRAY_ARCH"
      ;;
  esac
}

resolve_xray_source() {
  local arch

  case "$INSTALL_SOURCE" in
    1)
      arch="$XRAY_ARCH"
      if [ "$arch" = "auto" ]; then
        arch="$(detect_xray_arch)"
      fi
      XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${arch}.zip"
      log "下载 Xray ${XRAY_VERSION} (${arch})"
      ;;
    2)
      log "使用自定义 URL: $XRAY_URL"
      ;;
    3)
      log "使用本地文件: $XRAY_ZIP_LOCAL"
      ;;
  esac
}

prepare_xray_zip() {
  TMP_DIR="$(mktemp -d /tmp/xray_install.XXXXXX)"

  if [ "$INSTALL_SOURCE" = "3" ]; then
    cp "$XRAY_ZIP_LOCAL" "$TMP_DIR/xray.zip"
  else
    curl --fail --location --retry 3 --connect-timeout 15 --output "$TMP_DIR/xray.zip" "$XRAY_URL"
  fi
}

install_xray() {
  local unpack_dir="$TMP_DIR/unpacked"
  local data_file

  mkdir -p "$unpack_dir" "$XRAY_DIR"
  unzip -oq "$TMP_DIR/xray.zip" -d "$unpack_dir"

  [ -f "$unpack_dir/xray" ] || die "压缩包中未找到 xray 可执行文件"
  install -m 0755 "$unpack_dir/xray" "$XRAY_BIN"

  for data_file in geoip.dat geosite.dat; do
    if [ -f "$unpack_dir/$data_file" ]; then
      install -m 0644 "$unpack_dir/$data_file" "$XRAY_DIR/$data_file"
    fi
  done
}

write_xray_config() {
  local new_uuid

  new_uuid="$("$XRAY_BIN" uuid)"

  ensure_parent_dir "$CONFIG_FILE"
  backup_file "$CONFIG_FILE"

  CONFIG_FILE_OUT="$CONFIG_FILE" \
  DOMAIN_VALUE="$DOMAIN" \
  PORT_VALUE="$PORT" \
  CERT_VALUE="$CERT_FILE" \
  KEY_VALUE="$KEY_FILE" \
  UUID_VALUE="$new_uuid" \
  FLOW_VALUE="$VLESS_FLOW" \
  REMARK_VALUE="$INITIAL_REMARK" \
  python3 - <<'PY'
import json
import os

path = os.environ["CONFIG_FILE_OUT"]
flow = os.environ["FLOW_VALUE"]
clients = []

if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            old_config = json.load(f)
        old_clients = old_config.get("inbounds", [{}])[0].get("settings", {}).get("clients", [])
        if isinstance(old_clients, list) and old_clients:
            clients = old_clients
    except (OSError, json.JSONDecodeError, KeyError, IndexError, TypeError):
        clients = []

if clients:
    for client in clients:
        if isinstance(client, dict) and flow and "flow" not in client:
            client["flow"] = flow
else:
    client = {
        "id": os.environ["UUID_VALUE"],
        "email": os.environ["REMARK_VALUE"],
    }
    if flow:
        client["flow"] = flow
    clients = [client]

config = {
    "log": {
        "loglevel": "warning",
    },
    "inbounds": [
        {
            "tag": "vless-vision",
            "listen": "0.0.0.0",
            "port": int(os.environ["PORT_VALUE"]),
            "protocol": "vless",
            "settings": {
                "clients": clients,
                "decryption": "none",
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": os.environ["DOMAIN_VALUE"],
                    "certificates": [
                        {
                            "certificateFile": os.environ["CERT_VALUE"],
                            "keyFile": os.environ["KEY_VALUE"],
                        },
                    ],
                    "minVersion": "1.3",
                    "cipherSuites": "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384",
                    "alpn": ["h2"],
                    "preferServerCipherSuites": False,
                    "rejectUnknownSni": False,
                },
                "sockopt": {
                    "tcpFastOpen": True,
                    "tcpKeepAliveIdle": 60,
                    "tcpNoDelay": True,
                },
            },
        },
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {},
        },
    ],
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

test_xray_config() {
  log "校验配置文件"
  "$XRAY_BIN" run -test -config "$CONFIG_FILE"
}

write_systemd_service() {
  ensure_parent_dir "$SERVICE_FILE"
  backup_file "$SERVICE_FILE"

  cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStart="$XRAY_BIN" run -config "$CONFIG_FILE"
Restart=on-failure
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

restart_service() {
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

write_info_file() {
  ensure_parent_dir "$INFO_FILE"
  VLESS_LINK="$(
    python3 - "$CONFIG_FILE" "$INFO_FILE" "$XRAY_DIR" "$XRAY_VERSION" "$DOMAIN" "$PORT" "$VLESS_FLOW" <<'PY'
import json
import os
import sys
from urllib.parse import quote, urlencode

config_file, info_file, xray_dir, version, domain, port, default_flow = sys.argv[1:8]

def make_link(uuid, remark, flow):
    params = [("encryption", "none")]
    if flow:
        params.append(("flow", flow))
    params.extend([
        ("security", "tls"),
        ("type", "tcp"),
        ("sni", domain),
    ])
    return f"vless://{uuid}@{domain}:{port}?{urlencode(params)}#{quote(remark, safe='')}"

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

clients = config.get("inbounds", [{}])[0].get("settings", {}).get("clients", [])
first_link = ""

os.makedirs(os.path.dirname(info_file) or ".", exist_ok=True)
with open(info_file, "w", encoding="utf-8") as f:
    f.write(f"Xray 安装目录: {xray_dir}\n")
    f.write(f"Xray 版本: {version}\n")
    f.write(f"域名: {domain}\n")
    f.write(f"端口: {port}\n\n")
    f.write("VLESS 连接信息:\n")
    f.write("================\n\n")
    for client in clients:
        uuid = client.get("id", "")
        remark = client.get("email", "未命名用户")
        flow = client.get("flow", default_flow)
        link = make_link(uuid, remark, flow)
        if not first_link:
            first_link = link
        f.write(f"备注: {remark}\n")
        f.write(f"UUID: {uuid}\n")
        f.write(f"VLESS 链接: {link}\n\n")

print(first_link)
PY
  )"
}

write_env_file() {
  ensure_parent_dir "$XRAY_ENV_FILE"
  {
    printf 'export XRAY_DIR=%q\n' "$XRAY_DIR"
    printf 'export CONFIG_FILE=%q\n' "$CONFIG_FILE"
    printf 'export BIN=%q\n' "$XRAY_BIN"
    printf 'export INFO_FILE=%q\n' "$INFO_FILE"
    printf 'export XUSER_SCRIPT=%q\n' "$XUSER_SCRIPT"
    printf 'export XRAY_VERSION=%q\n' "$XRAY_VERSION"
    printf 'export VLESS_FLOW=%q\n' "$VLESS_FLOW"
    printf 'export SYSTEMD_DIR=%q\n' "$SYSTEMD_DIR"
    printf 'export SERVICE_NAME=%q\n' "$SERVICE_NAME"
    printf 'export DOMAIN=%q\n' "$DOMAIN"
    printf 'export PORT=%q\n' "$PORT"
  } > "$XRAY_ENV_FILE"
  chmod 600 "$XRAY_ENV_FILE"
}

generate_xuser_script() {
  ensure_parent_dir "$XUSER_SCRIPT"

  {
    printf '#!/bin/bash\n'
    printf 'set -Eeuo pipefail\n'
    printf 'set +H\n\n'
    printf 'XRAY_ENV_FILE=%q\n\n' "$XRAY_ENV_FILE"
    cat <<'EOFXUSER'

if [ -r "$XRAY_ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$XRAY_ENV_FILE"
fi

XRAY_DIR="${XRAY_DIR:-/root/xray}"
CONFIG_FILE="${CONFIG_FILE:-$XRAY_DIR/config.json}"
BIN="${BIN:-$XRAY_DIR/xray}"
INFO_FILE="${INFO_FILE:-/root/xray_info.txt}"
XUSER_SCRIPT="${XUSER_SCRIPT:-/root/xuser.sh}"
XRAY_VERSION="${XRAY_VERSION:-unknown}"
VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
SYSTEMD_DIR="${SYSTEMD_DIR%/}"
SERVICE_NAME="${SERVICE_NAME:-xray}"
SERVICE_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}.service"
DOMAIN="${DOMAIN:-}"
PORT="${PORT:-}"

err() {
  echo "[ERR] $*" >&2
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "请使用 root 用户运行此操作"
    return 1
  fi
}

require_runtime() {
  if ! command -v python3 >/dev/null 2>&1; then
    err "缺少 python3"
    return 1
  fi
  if [ ! -x "$BIN" ]; then
    err "找不到 Xray 可执行文件: $BIN"
    return 1
  fi
  if [ ! -f "$CONFIG_FILE" ]; then
    err "找不到配置文件: $CONFIG_FILE"
    return 1
  fi
}

get_info_value() {
  local key="$1"

  [ -f "$INFO_FILE" ] || return 0
  awk -F': ' -v key="$key" '
    index($0, key ":") == 1 {
      sub("^[^:]*: ?", "")
      value=$0
    }
    END { print value }
  ' "$INFO_FILE"
}

current_domain() {
  if [ -n "${DOMAIN:-}" ]; then
    printf '%s\n' "$DOMAIN"
  elif [ -f "$CONFIG_FILE" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$CONFIG_FILE" <<'PY' 2>/dev/null || get_info_value "域名"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    config = json.load(f)

print(config["inbounds"][0]["streamSettings"]["tlsSettings"]["serverName"])
PY
  else
    get_info_value "域名"
  fi
}

current_port() {
  if [ -n "${PORT:-}" ]; then
    printf '%s\n' "$PORT"
  elif [ -f "$CONFIG_FILE" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$CONFIG_FILE" <<'PY' 2>/dev/null || get_info_value "端口"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    config = json.load(f)

print(config["inbounds"][0]["port"])
PY
  else
    get_info_value "端口"
  fi
}

make_backup() {
  local dir
  local backup

  dir="$(dirname "$CONFIG_FILE")"
  backup="$(mktemp "$dir/.config.json.bak.XXXXXX")"
  cp -a "$CONFIG_FILE" "$backup"
  printf '%s\n' "$backup"
}

restore_backup() {
  local backup="$1"

  cp -a "$backup" "$CONFIG_FILE"
  rm -f "$backup"
}

run_config_test() {
  "$BIN" run -test -config "$CONFIG_FILE" >/dev/null
}

restart_xray() {
  if ! command -v systemctl >/dev/null 2>&1; then
    err "当前系统不支持 systemd"
    return 1
  fi
  systemctl restart "$SERVICE_NAME"
}

update_info() {
  local domain
  local port

  require_runtime || return 1
  domain="$(current_domain)"
  port="$(current_port)"

  if [ -z "$domain" ] || [ -z "$port" ]; then
    err "无法读取域名或端口"
    return 1
  fi

  python3 - "$CONFIG_FILE" "$INFO_FILE" "$XRAY_DIR" "$XRAY_VERSION" "$domain" "$port" "$VLESS_FLOW" <<'PY'
import json
import os
import sys
from urllib.parse import quote, urlencode

config_file, info_file, xray_dir, version, domain, port, default_flow = sys.argv[1:8]

def clients_from(config):
    try:
        clients = config["inbounds"][0]["settings"].get("clients", [])
    except (KeyError, IndexError, TypeError) as exc:
        raise SystemExit(f"[ERR] 无法读取 clients: {exc}")
    if not isinstance(clients, list):
        raise SystemExit("[ERR] clients 不是数组")
    return clients

def make_link(uuid, remark, flow):
    params = [("encryption", "none")]
    if flow:
        params.append(("flow", flow))
    params.extend([
        ("security", "tls"),
        ("type", "tcp"),
        ("sni", domain),
    ])
    return f"vless://{uuid}@{domain}:{port}?{urlencode(params)}#{quote(remark, safe='')}"

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

clients = clients_from(config)
os.makedirs(os.path.dirname(info_file) or ".", exist_ok=True)

with open(info_file, "w", encoding="utf-8") as f:
    f.write(f"Xray 安装目录: {xray_dir}\n")
    f.write(f"Xray 版本: {version}\n")
    f.write(f"域名: {domain}\n")
    f.write(f"端口: {port}\n\n")
    f.write("VLESS 连接信息:\n")
    f.write("================\n\n")
    for client in clients:
        uuid = client.get("id", "")
        remark = client.get("email", "未命名用户")
        flow = client.get("flow", default_flow)
        f.write(f"备注: {remark}\n")
        f.write(f"UUID: {uuid}\n")
        f.write(f"VLESS 链接: {make_link(uuid, remark, flow)}\n\n")
PY
}

add_user() {
  local remark
  local uuid
  local backup

  require_root || return 1
  require_runtime || return 1

  read -r -p "请输入用户备注（例如: alice-iphone）: " remark
  if [ -z "$remark" ]; then
    err "备注不能为空"
    return 1
  fi

  uuid="$("$BIN" uuid)"
  backup="$(make_backup)" || return 1

  if ! python3 - "$CONFIG_FILE" "$uuid" "$remark" "$VLESS_FLOW" <<'PY'
import json
import os
import sys
import tempfile

config_file, uuid, remark, flow = sys.argv[1:5]

def save_json(path, data):
    directory = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(prefix=".config.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

try:
    clients = config["inbounds"][0]["settings"].setdefault("clients", [])
except (KeyError, IndexError, TypeError) as exc:
    raise SystemExit(f"[ERR] 无法读取 clients: {exc}")

if not isinstance(clients, list):
    raise SystemExit("[ERR] clients 不是数组")
if any(client.get("email") == remark for client in clients):
    raise SystemExit("[ERR] 备注已存在")

client = {
    "id": uuid,
    "email": remark,
}
if flow:
    client["flow"] = flow

clients.append(client)
save_json(config_file, config)
PY
  then
    rm -f "$backup"
    return 1
  fi

  if ! run_config_test; then
    err "配置验证失败，已回滚"
    restore_backup "$backup"
    return 1
  fi

  rm -f "$backup"
  update_info || return 1
  restart_xray || return 1

  echo "[OK] 添加成功"
  echo "备注: $remark"
  echo "UUID: $uuid"
  echo "[OK] Xray 已重启"
}

del_user() {
  local key
  local backup

  require_root || return 1
  require_runtime || return 1

  echo "=== 删除用户 ==="
  list_user || true
  echo
  read -r -p "请输入要删除的 UUID 或备注: " key
  if [ -z "$key" ]; then
    echo "取消"
    return 0
  fi

  backup="$(make_backup)" || return 1
  if ! python3 - "$CONFIG_FILE" "$key" <<'PY'
import json
import os
import sys
import tempfile

config_file, key = sys.argv[1:3]

def save_json(path, data):
    directory = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(prefix=".config.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

try:
    clients = config["inbounds"][0]["settings"].get("clients", [])
except (KeyError, IndexError, TypeError) as exc:
    raise SystemExit(f"[ERR] 无法读取 clients: {exc}")

new_clients = [
    client for client in clients
    if client.get("id") != key and client.get("email") != key
]
if len(new_clients) == len(clients):
    raise SystemExit("[ERR] 找不到用户")

config["inbounds"][0]["settings"]["clients"] = new_clients
save_json(config_file, config)
PY
  then
    rm -f "$backup"
    return 1
  fi

  if ! run_config_test; then
    err "配置验证失败，已回滚"
    restore_backup "$backup"
    return 1
  fi

  rm -f "$backup"
  update_info || return 1
  restart_xray || return 1
  echo "[OK] 删除成功，Xray 已重启"
}

list_user() {
  local domain
  local port

  require_runtime || return 1
  domain="$(current_domain)"
  port="$(current_port)"

  if [ -z "$domain" ] || [ -z "$port" ]; then
    err "无法读取域名或端口"
    return 1
  fi

  echo "=== 当前用户列表 ==="
  python3 - "$CONFIG_FILE" "$domain" "$port" "$VLESS_FLOW" <<'PY'
import json
import sys
from urllib.parse import quote, urlencode

config_file, domain, port, default_flow = sys.argv[1:5]

def make_link(uuid, remark, flow):
    params = [("encryption", "none")]
    if flow:
        params.append(("flow", flow))
    params.extend([
        ("security", "tls"),
        ("type", "tcp"),
        ("sni", domain),
    ])
    return f"vless://{uuid}@{domain}:{port}?{urlencode(params)}#{quote(remark, safe='')}"

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

clients = config.get("inbounds", [{}])[0].get("settings", {}).get("clients", [])
if not clients:
    print("（暂无用户）")
    raise SystemExit(0)

for index, client in enumerate(clients, 1):
    remark = client.get("email", "未命名用户")
    uuid = client.get("id", "")
    flow = client.get("flow", default_flow)
    print(f"{index}. 备注: {remark}")
    print(f"   UUID: {uuid}")
    print(f"   链接: {make_link(uuid, remark, flow)}")
    print()
PY
}

uninstall() {
  local confirm

  require_root || return 1
  case "$XRAY_DIR" in
    ""|/|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      err "拒绝删除高风险目录: ${XRAY_DIR:-<empty>}"
      return 1
      ;;
  esac

  read -r -p "[WARN] 确认卸载 Xray？此操作不可恢复 [y/N]: " confirm
  case "$confirm" in
    y|Y) ;;
    *) echo "已取消"; return 0 ;;
  esac

  echo "==> 停止 Xray 服务"
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload

  echo "==> 删除 Xray 文件"
  rm -rf "$XRAY_DIR"
  rm -f "$INFO_FILE" "$XRAY_ENV_FILE" "$XUSER_SCRIPT"

  echo "[OK] 已完全卸载 Xray"
}

show_menu() {
  echo
  echo "╔════════════════════════════════════════╗"
  echo "║  Xray 用户管理工具 (xuser.sh)          ║"
  echo "╚════════════════════════════════════════╝"
  echo "1) 添加用户"
  echo "2) 删除用户"
  echo "3) 列出所有用户"
  echo "4) 更新 xray_info.txt"
  echo "5) 一键卸载 Xray"
  echo "0) 退出"
  echo
}

while true; do
  show_menu
  read -r -p "请选择操作 [0-5]: " choice

  case "$choice" in
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
  } > "$XUSER_SCRIPT"

  chmod +x "$XUSER_SCRIPT"
}

echo "========== Xray VLESS 自动部署脚本 =========="

if [ ! -f "$CONFIG_FILE_PATH" ]; then
  echo "==> 首次运行，需要配置"
  if [ -t 0 ]; then
    read -r -p "请输入配置文件保存路径 [默认 $CONFIG_FILE_PATH]: " custom_path
    if [ -n "${custom_path:-}" ]; then
      CONFIG_FILE_PATH="$custom_path"
    fi
  fi
  generate_config_template
  exit 0
fi

load_config || {
  generate_config_template
  exit 0
}

normalize_config
validate_config
require_root

log "检测运行环境"
ensure_dependencies

log "下载和安装 Xray"
resolve_xray_source
prepare_xray_zip
install_xray

echo "==> Xray 版本确认"
"$XRAY_BIN" version

log "生成 Xray 配置"
echo "    域名: $DOMAIN"
echo "    端口: $PORT"
echo "    证书: $CERT_FILE"
echo "    私钥: $KEY_FILE"
echo "    Xray 目录: $XRAY_DIR"
write_xray_config
test_xray_config

log "写入 systemd 服务"
write_systemd_service
restart_service

write_info_file
write_env_file
generate_xuser_script

echo
echo "========== 部署完成 =========="
echo "$VLESS_LINK"
echo "已保存到: $INFO_FILE"
ok "xuser.sh 已生成: $XUSER_SCRIPT"
ok "环境配置已保存: $XRAY_ENV_FILE"
ok "配置文件已保存: $CONFIG_FILE_PATH"
echo
echo "运行命令：bash $XUSER_SCRIPT 进行用户管理"
