#!/bin/bash
set -Eeuo pipefail
umask 077

DEFAULT_CONFIG_FILE="/root/xray_relay_install.conf"
DEFAULT_VLESS_FLOW="xtls-rprx-vision"
DEFAULT_SERVICE_NAME="xray-relay"

if [ "$#" -gt 1 ]; then
  echo "用法: $0 [配置文件路径]" >&2
  exit 2
fi

CONFIG_FILE_PATH="${1:-$DEFAULT_CONFIG_FILE}"
TMP_DIR=""
XRAY_CANDIDATE=""
CONFIG_CANDIDATE=""
BACKUP_FILE_PATH=""
XRAY_BACKUP_PATH=""
CONFIG_BACKUP_PATH=""
SERVICE_BACKUP_PATH=""
GEOIP_BACKUP_PATH=""
GEOSITE_BACKUP_PATH=""
CONFIG_CHANGED=0
XRAY_CHANGED=0
SERVICE_CHANGED=0
GEOIP_CHANGED=0
GEOSITE_CHANGED=0
SERVICE_WAS_ACTIVE=0
SERVICE_WAS_ENABLED=0
SERVICE_ENABLE_ATTEMPTED=0

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
  mkdir -p -m 0700 "$dir"
}

backup_file() {
  local file="$1"
  local backup

  BACKUP_FILE_PATH=""
  [ -f "$file" ] || return 0
  backup="$(mktemp "${file}.bak.XXXXXX")" || return 1
  if ! cp -a "$file" "$backup" || ! chmod 600 "$backup"; then
    rm -f "$backup"
    return 1
  fi
  BACKUP_FILE_PATH="$backup"
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
# Xray 入口服务器自动安装配置文件
# 配置文件采用 shell 变量格式，请只保存到可信路径。

# 入口服务器参数
DOMAIN="example.com"
PORT="443"
CERT_FILE="/path/to/cert.pem"
KEY_FILE="/path/to/key.pem"

# 出口服务器 VLESS 参数（仅支持 VLESS + TCP + TLS）
UPSTREAM_ADDRESS="exit.example.com"
UPSTREAM_PORT="443"
UPSTREAM_UUID=""
UPSTREAM_SNI=""
UPSTREAM_FLOW="xtls-rprx-vision"

# 可选项
XRAY_DIR="/root/xray_relay"
# XRAY_VERSION 会从安装后的 Xray 二进制自动识别，无需手动设置。
XRAY_ARCH="auto"
VLESS_FLOW="xtls-rprx-vision"
INITIAL_REMARK="初始用户"

# 下载方式：1=GitHub 最新版, 2=用户指定下载链接, 3=本地 zip 文件
INSTALL_SOURCE="1"
XRAY_URL=""
XRAY_ZIP_LOCAL=""

# 文件保存路径
INFO_FILE="/root/xray_relay_info.txt"
XUSER_SCRIPT="/root/xuser_relay.sh"
XRAY_ENV_FILE="/root/.xray_relay_env"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="xray-relay"
CONFIGEOF

  chmod 600 "$template_path"
  ok "已生成配置文件模板: $template_path"
  echo "请编辑配置文件并填写参数后，再次运行本脚本"
  echo
  echo "关键参数说明:"
  echo "  DOMAIN        - 入口服务器域名（必填，不能保留 example.com）"
  echo "  PORT          - 监听端口（必填，1-65535）"
  echo "  CERT_FILE     - SSL 证书文件路径（必填）"
  echo "  KEY_FILE      - SSL 私钥文件路径（必填）"
  echo "  UPSTREAM_*    - 出口服务器 VLESS 节点参数"
  echo "  INSTALL_SOURCE - 1=GitHub 最新版, 2=用户指定下载链接, 3=本地 zip 文件"
  echo "  XRAY_URL      - INSTALL_SOURCE=2 时填写下载链接"
  echo "  XRAY_ZIP_LOCAL- INSTALL_SOURCE=3 时填写本地 zip 文件路径"
  echo "  XRAY_ARCH     - auto/64/arm64-v8a/arm32-v7a 等 release 架构名"
  echo
}

normalize_config() {
  DOMAIN="${DOMAIN:-}"
  PORT="${PORT:-}"
  CERT_FILE="${CERT_FILE:-}"
  KEY_FILE="${KEY_FILE:-}"
  UPSTREAM_ADDRESS="${UPSTREAM_ADDRESS:-}"
  UPSTREAM_PORT="${UPSTREAM_PORT:-}"
  UPSTREAM_UUID="${UPSTREAM_UUID:-}"
  UPSTREAM_SNI="${UPSTREAM_SNI:-$UPSTREAM_ADDRESS}"
  UPSTREAM_FLOW="${UPSTREAM_FLOW:-$DEFAULT_VLESS_FLOW}"

  XRAY_DIR="${XRAY_DIR:-/root/xray_relay}"
  while [[ "$XRAY_DIR" == */ ]]; do
    XRAY_DIR="${XRAY_DIR%/}"
  done
  XRAY_ARCH="${XRAY_ARCH:-auto}"
  VLESS_FLOW="${VLESS_FLOW:-$DEFAULT_VLESS_FLOW}"
  INITIAL_REMARK="${INITIAL_REMARK:-初始用户}"

  INSTALL_SOURCE="${INSTALL_SOURCE:-1}"
  XRAY_URL="${XRAY_URL:-}"
  XRAY_ZIP_LOCAL="${XRAY_ZIP_LOCAL:-}"

  INFO_FILE="${INFO_FILE:-/root/xray_relay_info.txt}"
  XUSER_SCRIPT="${XUSER_SCRIPT:-/root/xuser_relay.sh}"
  XRAY_ENV_FILE="${XRAY_ENV_FILE:-/root/.xray_relay_env}"
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
  [[ "$XRAY_DIR" == /* ]] || die "XRAY_DIR 必须是绝对路径"
  case "$XRAY_DIR" in
    *"/../"*|*/..)
      die "XRAY_DIR 不能包含 .. 路径片段"
      ;;
  esac

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
  [ -n "$UPSTREAM_ADDRESS" ] || die "配置文件中缺少 UPSTREAM_ADDRESS"
  [ -n "$UPSTREAM_PORT" ] || die "配置文件中缺少 UPSTREAM_PORT"
  [ -n "$UPSTREAM_UUID" ] || die "配置文件中缺少 UPSTREAM_UUID"
  [ -n "$UPSTREAM_SNI" ] || die "配置文件中缺少 UPSTREAM_SNI"

  if [ "${#DOMAIN}" -gt 253 ] ||
    ! [[ "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$ ]]; then
    die "DOMAIN 必须是有效的 DNS 主机名，且每个标签不能以连字符开头或结尾"
  fi
  if contains_newline "$DOMAIN"; then
    die "DOMAIN 不能包含换行符"
  fi
  if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    die "PORT 必须是 1-65535 之间的数字"
  fi
  if ! [[ "$UPSTREAM_PORT" =~ ^[0-9]+$ ]] || [ "$UPSTREAM_PORT" -lt 1 ] || [ "$UPSTREAM_PORT" -gt 65535 ]; then
    die "UPSTREAM_PORT 必须是 1-65535 之间的数字"
  fi
  if contains_newline "$UPSTREAM_ADDRESS" || contains_newline "$UPSTREAM_SNI" ||
    ! [[ "$UPSTREAM_ADDRESS" =~ ^[A-Za-z0-9.:-]+$ ]] ||
    ! [[ "$UPSTREAM_SNI" =~ ^[A-Za-z0-9.:-]+$ ]]; then
    die "UPSTREAM_ADDRESS 和 UPSTREAM_SNI 必须是有效的主机名或 IP 地址"
  fi
  if ! [[ "$UPSTREAM_UUID" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]]; then
    die "UPSTREAM_UUID 必须是有效的 UUID"
  fi
  if [ -n "$UPSTREAM_FLOW" ] && ! [[ "$UPSTREAM_FLOW" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "UPSTREAM_FLOW 只能包含字母、数字、点、下划线和连字符"
  fi
  if ! [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    die "SERVICE_NAME 只能包含字母、数字、点、下划线、@ 和连字符"
  fi

  validate_xray_dir
  validate_path_value "CERT_FILE" "$CERT_FILE"
  validate_path_value "KEY_FILE" "$KEY_FILE"
  validate_path_value "UPSTREAM_ADDRESS" "$UPSTREAM_ADDRESS"
  validate_path_value "UPSTREAM_SNI" "$UPSTREAM_SNI"
  validate_path_value "INFO_FILE" "$INFO_FILE"
  validate_path_value "XUSER_SCRIPT" "$XUSER_SCRIPT"
  validate_path_value "XRAY_ENV_FILE" "$XRAY_ENV_FILE"
  validate_path_value "SYSTEMD_DIR" "$SYSTEMD_DIR"
  contains_newline "$INITIAL_REMARK" && die "INITIAL_REMARK 不能包含换行符"
  if [ -n "$VLESS_FLOW" ] && ! [[ "$VLESS_FLOW" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "VLESS_FLOW 只能包含字母、数字、点、下划线和连字符"
  fi
  if ! [[ "$XRAY_ARCH" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "XRAY_ARCH 只能包含字母、数字、点、下划线和连字符"
  fi

  [ -f "$CERT_FILE" ] || die "证书文件不存在: $CERT_FILE"
  [ -r "$CERT_FILE" ] || die "证书文件不可读: $CERT_FILE"
  [ -f "$KEY_FILE" ] || die "私钥文件不存在: $KEY_FILE"
  [ -r "$KEY_FILE" ] || die "私钥文件不可读: $KEY_FILE"

  case "$INSTALL_SOURCE" in
    1) ;;
    2)
      [ -n "$XRAY_URL" ] || die "INSTALL_SOURCE=2 时必须填写 XRAY_URL"
      [[ "$XRAY_URL" =~ ^https?://[^[:space:]]+$ ]] ||
        die "XRAY_URL 必须是有效的 HTTP 或 HTTPS URL"
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

get_latest_xray_version() {
  local tag

  tag="$(curl --fail --location --retry 3 --connect-timeout 15 --max-time 30 --silent --show-error \
    --proto '=https' --proto-redir '=https' \
    "https://api.github.com/repos/XTLS/Xray-core/releases/latest" |
    python3 -c 'import json, re, sys; tag=json.load(sys.stdin).get("tag_name", ""); print(tag if re.fullmatch(r"v?[0-9]+(\.[0-9]+){2}([.-][A-Za-z0-9.-]+)?", tag) else "")')" \
    || die "无法获取 Xray 最新版本"
  [ -n "$tag" ] || die "GitHub 返回的 Xray 版本号无效"
  printf '%s\n' "${tag#v}"
}

resolve_xray_source() {
  local arch

  case "$INSTALL_SOURCE" in
    1)
      XRAY_VERSION="$(get_latest_xray_version)"
      arch="$XRAY_ARCH"
      if [ "$arch" = "auto" ]; then
        arch="$(detect_xray_arch)"
      fi
      XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${arch}.zip"
      log "从 GitHub 下载最新版 Xray ${XRAY_VERSION} (${arch})"
      ;;
    2)
      log "从用户指定链接下载 Xray: $XRAY_URL"
      ;;
    3)
      log "从本地 zip 文件安装 Xray: $XRAY_ZIP_LOCAL"
      ;;
  esac
}

prepare_xray_zip() {
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xray_install.XXXXXX")"

  if [ "$INSTALL_SOURCE" = "3" ]; then
    cp "$XRAY_ZIP_LOCAL" "$TMP_DIR/xray.zip"
  else
    curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 --show-error \
      --proto '=https,http' --proto-redir '=https,http' \
      --output "$TMP_DIR/xray.zip" "$XRAY_URL"
  fi
}

install_xray() {
  local unpack_dir="$TMP_DIR/unpacked"
  mkdir -p -m 0700 "$unpack_dir"
  unzip -oq "$TMP_DIR/xray.zip" -d "$unpack_dir"

  [ -f "$unpack_dir/xray" ] || die "压缩包中未找到 xray 可执行文件"
  chmod 0755 "$unpack_dir/xray"
  XRAY_CANDIDATE="$unpack_dir/xray"
}

detect_candidate_xray_version() {
  local version_output

  version_output="$("$XRAY_CANDIDATE" version)" || die "无法读取待安装的 Xray 版本"
  XRAY_VERSION="$(printf '%s\n' "$version_output" | awk 'NR == 1 && $1 == "Xray" { print $2 }')"
  [ -n "$XRAY_VERSION" ] || die "无法从 Xray 版本信息中识别版本号"
  printf '%s\n' "$version_output"
}

write_xray_config() {
  local new_uuid

  new_uuid="$("$XRAY_CANDIDATE" uuid)"

  CONFIG_CANDIDATE="$TMP_DIR/config.json"

  CONFIG_FILE_OUT="$CONFIG_FILE" \
  CONFIG_FILE_CANDIDATE="$CONFIG_CANDIDATE" \
  DOMAIN_VALUE="$DOMAIN" \
  PORT_VALUE="$PORT" \
  CERT_VALUE="$CERT_FILE" \
  KEY_VALUE="$KEY_FILE" \
  UUID_VALUE="$new_uuid" \
  FLOW_VALUE="$VLESS_FLOW" \
  REMARK_VALUE="$INITIAL_REMARK" \
  UPSTREAM_ADDRESS_VALUE="$UPSTREAM_ADDRESS" \
  UPSTREAM_PORT_VALUE="$UPSTREAM_PORT" \
  UPSTREAM_UUID_VALUE="$UPSTREAM_UUID" \
  UPSTREAM_SNI_VALUE="$UPSTREAM_SNI" \
  UPSTREAM_FLOW_VALUE="$UPSTREAM_FLOW" \
  python3 - <<'PY'
import json
import os
import tempfile

path = os.environ["CONFIG_FILE_CANDIDATE"]
existing_path = os.environ["CONFIG_FILE_OUT"]
flow = os.environ["FLOW_VALUE"]
upstream_flow = os.environ["UPSTREAM_FLOW_VALUE"]
clients = []

if os.path.exists(existing_path):
    try:
        with open(existing_path, "r", encoding="utf-8") as f:
            old_config = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"[ERR] 无法读取现有配置，拒绝覆盖: {exc}")

    if not isinstance(old_config, dict):
        raise SystemExit("[ERR] 现有配置格式无效，拒绝覆盖")
    inbounds = old_config.get("inbounds", [])
    if not isinstance(inbounds, list):
        raise SystemExit("[ERR] 现有配置中的 inbounds 格式无效，拒绝覆盖")
    if inbounds:
        first_inbound = inbounds[0]
        if not isinstance(first_inbound, dict):
            raise SystemExit("[ERR] 现有配置中的 inbound 格式无效，拒绝覆盖")
        settings = first_inbound.get("settings", {})
        if not isinstance(settings, dict):
            raise SystemExit("[ERR] 现有配置中的 settings 格式无效，拒绝覆盖")
        old_clients = settings.get("clients", [])
        if not isinstance(old_clients, list):
            raise SystemExit("[ERR] 现有配置中的 clients 格式无效，拒绝覆盖")
        clients = old_clients

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
                    "rejectUnknownSni": True,
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
            "tag": "upstream-vless",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": os.environ["UPSTREAM_ADDRESS_VALUE"],
                        "port": int(os.environ["UPSTREAM_PORT_VALUE"]),
                        "users": [
                            {
                                "id": os.environ["UPSTREAM_UUID_VALUE"],
                                "encryption": "none",
                                **({"flow": upstream_flow} if upstream_flow else {}),
                            },
                        ],
                    },
                ],
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": os.environ["UPSTREAM_SNI_VALUE"],
                },
            },
        },
    ],
}

directory = os.path.dirname(path) or "."
fd, temp_path = tempfile.mkstemp(prefix=".config.", suffix=".tmp", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(temp_path, 0o600)
    os.replace(temp_path, path)
except Exception:
    try:
        os.unlink(temp_path)
    except FileNotFoundError:
        pass
    raise
PY
}

test_xray_config() {
  log "校验配置文件"
  "$XRAY_CANDIDATE" run -test -config "$CONFIG_CANDIDATE"
}

commit_xray_config() {
  local replacement

  ensure_parent_dir "$CONFIG_FILE" || return 1
  backup_file "$CONFIG_FILE" || return 1
  CONFIG_BACKUP_PATH="$BACKUP_FILE_PATH"
  replacement="${CONFIG_FILE}.new.$$"
  install -m 0600 "$CONFIG_CANDIDATE" "$replacement" || return 1
  if ! mv -f "$replacement" "$CONFIG_FILE"; then
    rm -f "$replacement"
    return 1
  fi
  CONFIG_CHANGED=1
}

commit_xray_install() {
  local replacement
  local data_file

  mkdir -p -m 0700 "$XRAY_DIR" || return 1
  backup_file "$XRAY_BIN" || return 1
  XRAY_BACKUP_PATH="$BACKUP_FILE_PATH"
  replacement="${XRAY_BIN}.new.$$"
  install -m 0755 "$XRAY_CANDIDATE" "$replacement" || return 1
  if ! mv -f "$replacement" "$XRAY_BIN"; then
    rm -f "$replacement"
    return 1
  fi
  XRAY_CHANGED=1

  for data_file in geoip.dat geosite.dat; do
    if [ -f "$TMP_DIR/unpacked/$data_file" ]; then
      backup_file "$XRAY_DIR/$data_file" || return 1
      case "$data_file" in
        geoip.dat)
          GEOIP_BACKUP_PATH="$BACKUP_FILE_PATH"
          GEOIP_CHANGED=1
          ;;
        geosite.dat)
          GEOSITE_BACKUP_PATH="$BACKUP_FILE_PATH"
          GEOSITE_CHANGED=1
          ;;
      esac
      replacement="$XRAY_DIR/.${data_file}.new.$$"
      install -m 0644 "$TMP_DIR/unpacked/$data_file" "$replacement" || return 1
      if ! mv -f "$replacement" "$XRAY_DIR/$data_file"; then
        rm -f "$replacement"
        return 1
      fi
    fi
  done
}

restore_deployment_file() {
  local target="$1"
  local backup="$2"

  if [ -n "$backup" ]; then
    cp -a "$backup" "$target"
  else
    rm -f "$target"
  fi
}

rollback_deployment() {
  local rollback_failed=0

  if [ "$CONFIG_CHANGED" -eq 1 ]; then
    restore_deployment_file "$CONFIG_FILE" "$CONFIG_BACKUP_PATH" ||
      { err "无法恢复配置文件"; rollback_failed=1; }
  fi
  if [ "$XRAY_CHANGED" -eq 1 ]; then
    restore_deployment_file "$XRAY_BIN" "$XRAY_BACKUP_PATH" ||
      { err "无法恢复 Xray 二进制文件"; rollback_failed=1; }
  fi
  if [ "$GEOIP_CHANGED" -eq 1 ]; then
    restore_deployment_file "$XRAY_DIR/geoip.dat" "$GEOIP_BACKUP_PATH" ||
      { err "无法恢复 geoip.dat"; rollback_failed=1; }
  fi
  if [ "$GEOSITE_CHANGED" -eq 1 ]; then
    restore_deployment_file "$XRAY_DIR/geosite.dat" "$GEOSITE_BACKUP_PATH" ||
      { err "无法恢复 geosite.dat"; rollback_failed=1; }
  fi
  if [ "$SERVICE_CHANGED" -eq 1 ]; then
    if [ "$SERVICE_ENABLE_ATTEMPTED" -eq 1 ]; then
      systemctl disable "$SERVICE_NAME" || rollback_failed=1
    fi
    restore_deployment_file "$SERVICE_FILE" "$SERVICE_BACKUP_PATH" ||
      { err "无法恢复 systemd unit"; rollback_failed=1; }
    systemctl daemon-reload || rollback_failed=1
    if [ "$SERVICE_WAS_ENABLED" -eq 1 ]; then
      systemctl enable "$SERVICE_NAME" || rollback_failed=1
    fi
    if [ "$SERVICE_WAS_ACTIVE" -eq 1 ]; then
      systemctl restart "$SERVICE_NAME" || {
        err "旧版 Xray 服务未能恢复启动"
        rollback_failed=1
      }
    else
      systemctl stop "$SERVICE_NAME" || rollback_failed=1
    fi
  fi
  [ "$rollback_failed" -eq 0 ]
}

write_systemd_service() {
  ensure_parent_dir "$SERVICE_FILE" || return 1
  backup_file "$SERVICE_FILE" || return 1
  SERVICE_BACKUP_PATH="$BACKUP_FILE_PATH"
  SERVICE_CHANGED=1

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
  chmod 0644 "$SERVICE_FILE"
}

restart_service() {
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    SERVICE_WAS_ACTIVE=1
  fi
  if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    SERVICE_WAS_ENABLED=1
  fi

  if ! systemctl daemon-reload; then
    err "systemd 重新加载失败，正在回滚部署"
    rollback_deployment || err "自动回滚未能完整完成，请检查备份文件"
    return 1
  fi
  SERVICE_ENABLE_ATTEMPTED=1
  if ! systemctl enable "$SERVICE_NAME" || ! systemctl restart "$SERVICE_NAME"; then
    err "systemd 服务启动失败，正在回滚部署"
    rollback_deployment || err "自动回滚未能完整完成，请检查备份文件"
    return 1
  fi
}

write_info_file() {
  ensure_parent_dir "$INFO_FILE"
  VLESS_LINK="$(
    python3 - "$CONFIG_FILE" "$INFO_FILE" "$XRAY_DIR" "$XRAY_VERSION" "$DOMAIN" "$PORT" "$VLESS_FLOW" <<'PY'
import json
import os
import sys
import tempfile
from urllib.parse import quote, urlencode

config_file, info_file, xray_dir, version, domain, port, default_flow = sys.argv[1:8]

def make_link(uuid, remark, flow, alpn):
    params = [("encryption", "none")]
    if flow:
        params.append(("flow", flow))
    params.extend([
        ("security", "tls"),
        ("type", "tcp"),
        ("sni", domain),
    ])
    if alpn:
        params.append(("alpn", alpn))
    return f"vless://{uuid}@{domain}:{port}?{urlencode(params)}#{quote(remark, safe='')}"

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

inbound = config.get("inbounds", [{}])[0]
stream_settings = inbound.get("streamSettings", {})
tls_settings = stream_settings.get("tlsSettings", {})
domain = tls_settings.get("serverName") or domain
port = str(inbound.get("port") or port)
alpn = tls_settings.get("alpn", [])
if isinstance(alpn, list):
    alpn = ",".join(alpn)
elif not isinstance(alpn, str):
    alpn = ""
clients = inbound.get("settings", {}).get("clients", [])
first_link = ""

os.makedirs(os.path.dirname(info_file) or ".", exist_ok=True)
info_dir = os.path.dirname(info_file) or "."
fd, temp_path = tempfile.mkstemp(prefix=".xray_info.", dir=info_dir)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
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
            link = make_link(uuid, remark, flow, alpn)
            if not first_link:
                first_link = link
            f.write(f"备注: {remark}\n")
            f.write(f"UUID: {uuid}\n")
            f.write(f"VLESS 链接: {link}\n\n")
    os.chmod(temp_path, 0o600)
    os.replace(temp_path, info_file)
except Exception:
    try:
        os.unlink(temp_path)
    except FileNotFoundError:
        pass
    raise

print(first_link)
PY
  )"
  chmod 600 "$INFO_FILE"
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
    printf 'export XRAY_ARCH=%q\n' "$XRAY_ARCH"
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
    printf '\n'
    printf 'umask 077\n\n'
    printf 'XRAY_ENV_FILE=%q\n\n' "$XRAY_ENV_FILE"
    cat <<'EOFXUSER'

if [ -r "$XRAY_ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$XRAY_ENV_FILE"
fi

XRAY_DIR="${XRAY_DIR:-/root/xray_relay}"
CONFIG_FILE="${CONFIG_FILE:-$XRAY_DIR/config.json}"
BIN="${BIN:-$XRAY_DIR/xray}"
INFO_FILE="${INFO_FILE:-/root/xray_relay_info.txt}"
XUSER_SCRIPT="${XUSER_SCRIPT:-/root/xuser_relay.sh}"
XRAY_VERSION="${XRAY_VERSION:-unknown}"
XRAY_ARCH="${XRAY_ARCH:-auto}"
VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
SYSTEMD_DIR="${SYSTEMD_DIR%/}"
SERVICE_NAME="${SERVICE_NAME:-xray-relay}"
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

read_config_field() {
  local field="$1"

  python3 - "$CONFIG_FILE" "$field" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    config = json.load(f)

inbounds = config.get("inbounds", [])
if not isinstance(inbounds, list) or not inbounds or not isinstance(inbounds[0], dict):
    raise SystemExit("[ERR] 配置文件中没有有效的 inbound")

inbound = inbounds[0]
if sys.argv[2] == "domain":
    stream_settings = inbound.get("streamSettings", {})
    if not isinstance(stream_settings, dict):
        raise SystemExit("[ERR] 配置文件中的 streamSettings 格式无效")
    tls_settings = stream_settings.get("tlsSettings", {})
    if not isinstance(tls_settings, dict):
        raise SystemExit("[ERR] 配置文件中的 tlsSettings 格式无效")
    value = tls_settings.get("serverName")
else:
    value = inbound.get("port")
print(value or "")
PY
}

current_domain() {
  local value

  value="$(read_config_field domain)" || return 1
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi

  if [ -n "${DOMAIN:-}" ]; then
    printf '%s\n' "$DOMAIN"
  else
    get_info_value "域名"
  fi
}

current_port() {
  local value

  value="$(read_config_field port)" || return 1
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi

  if [ -n "${PORT:-}" ]; then
    printf '%s\n' "$PORT"
  else
    get_info_value "端口"
  fi
}

make_backup() {
  local dir
  local backup

  dir="$(dirname "$CONFIG_FILE")"
  backup="$(mktemp "$dir/.config.json.bak.XXXXXX")" || return 1
  if ! cp -a "$CONFIG_FILE" "$backup" || ! chmod 600 "$backup"; then
    rm -f "$backup"
    return 1
  fi
  printf '%s\n' "$backup"
}

restore_backup() {
  local backup="$1"

  cp -a "$backup" "$CONFIG_FILE" && rm -f "$backup"
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

finish_config_change() {
  local backup="$1"

  if ! run_config_test; then
    err "配置验证失败，已回滚"
    restore_backup "$backup" || err "回滚失败，备份保留在: $backup"
    return 1
  fi

  if ! update_info; then
    err "更新用户信息失败，正在回滚"
    if ! restore_backup "$backup"; then
      err "回滚失败，备份保留在: $backup"
      return 1
    fi
    update_info || err "回滚后仍无法更新用户信息"
    return 1
  fi

  if ! restart_xray; then
    err "服务重启失败，正在恢复旧配置"
    if ! restore_backup "$backup"; then
      err "回滚失败，备份保留在: $backup"
      return 1
    fi
    update_info || {
      err "已恢复旧配置，但无法恢复用户信息"
      return 1
    }
    restart_xray || {
      err "旧配置已恢复，但服务重启失败"
      return 1
    }
    return 1
  fi

  rm -f "$backup"
}

stop_xray() {
  require_root || return 1
  systemctl stop "$SERVICE_NAME" && echo "[OK] Xray 已关闭"
}

start_xray() {
  require_root || return 1
  systemctl start "$SERVICE_NAME" && echo "[OK] Xray 已启动"
}

show_xray_logs() {
  if ! command -v journalctl >/dev/null 2>&1; then
    err "当前系统没有 journalctl"
    return 1
  fi
  journalctl -u "$SERVICE_NAME" -n 100 --no-pager
}

latest_release_version() {
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 30 --silent --show-error \
    --proto '=https' --proto-redir '=https' \
    "https://api.github.com/repos/XTLS/Xray-core/releases/latest" |
    python3 -c 'import json, re, sys; tag=json.load(sys.stdin).get("tag_name", ""); print(tag[1:] if tag.startswith("v") and re.fullmatch(r"v[0-9]+(\.[0-9]+){2}([.-][A-Za-z0-9.-]+)?", tag) else tag if re.fullmatch(r"[0-9]+(\.[0-9]+){2}([.-][A-Za-z0-9.-]+)?", tag) else "")'
}

update_xray_latest() {
  local version
  local arch
  local update_dir
  local candidate
  local backup
  local replacement
  local was_active=0
  local command_name

  require_root || return 1
  require_runtime || return 1
  for command_name in curl unzip python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      err "缺少依赖: $command_name"
      return 1
    fi
  done
  if ! command -v systemctl >/dev/null 2>&1; then
    err "当前系统不支持 systemd"
    return 1
  fi

  version="$(latest_release_version)" || {
    err "无法获取 Xray 最新版本"
    return 1
  }
  if [ -z "$version" ]; then
    err "GitHub 返回的 Xray 版本号无效"
    return 1
  fi

  arch="$XRAY_ARCH"
  if [ "$arch" = "auto" ]; then
    case "$(uname -m)" in
      x86_64|amd64) arch="64" ;;
      aarch64|arm64) arch="arm64-v8a" ;;
      armv7l|armv7*) arch="arm32-v7a" ;;
      armv6l|armv6*) arch="arm32-v6" ;;
      i386|i686) arch="32" ;;
      *) err "无法自动识别架构，请在环境文件中设置 XRAY_ARCH"; return 1 ;;
    esac
  fi

  update_dir="$(mktemp -d "${TMPDIR:-/tmp}/xray_update.XXXXXX")" || return 1
  candidate="$update_dir/unpacked/xray"
  backup="$update_dir/xray.old"
  replacement="$(mktemp "${BIN}.new.XXXXXX")" || {
    rm -rf "$update_dir"
    return 1
  }
  if ! curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 --show-error \
    --proto '=https' --proto-redir '=https' \
    --output "$update_dir/xray.zip" \
    "https://github.com/XTLS/Xray-core/releases/download/v${version}/Xray-linux-${arch}.zip"; then
    err "下载 Xray ${version} 失败"
    rm -f "$replacement"
    rm -rf "$update_dir"
    return 1
  fi
  if ! unzip -oq "$update_dir/xray.zip" -d "$update_dir/unpacked" || [ ! -f "$candidate" ]; then
    err "最新版压缩包无效或缺少 xray 可执行文件"
    rm -f "$replacement"
    rm -rf "$update_dir"
    return 1
  fi
  chmod 0755 "$candidate"
  if ! "$candidate" run -test -config "$CONFIG_FILE"; then
    err "最新版无法通过当前配置校验，未更新"
    rm -f "$replacement"
    rm -rf "$update_dir"
    return 1
  fi

  cp -a "$BIN" "$backup" || {
    err "无法备份当前 Xray 二进制文件"
    rm -f "$replacement"
    rm -rf "$update_dir"
    return 1
  }
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    was_active=1
    if ! systemctl stop "$SERVICE_NAME"; then
      err "无法停止 Xray 服务，未执行更新"
      rm -f "$replacement"
      rm -rf "$update_dir"
      return 1
    fi
  fi

  if ! install -m 0755 "$candidate" "$replacement" || ! mv -f "$replacement" "$BIN"; then
    err "替换 Xray 二进制失败"
    rm -f "$replacement"
    if [ "$was_active" -eq 1 ]; then
      systemctl start "$SERVICE_NAME" || err "旧版 Xray 服务未能恢复启动"
    fi
    rm -rf "$update_dir"
    return 1
  fi
  if [ "$was_active" -eq 1 ] && ! systemctl start "$SERVICE_NAME"; then
    err "最新版启动失败，正在恢复旧版本"
    if ! install -m 0755 "$backup" "$replacement" || ! mv -f "$replacement" "$BIN"; then
      err "旧版 Xray 二进制恢复失败"
      rm -f "$replacement"
      rm -rf "$update_dir"
      return 1
    fi
    systemctl start "$SERVICE_NAME" || err "旧版 Xray 服务未能恢复启动"
    rm -rf "$update_dir"
    return 1
  fi

  XRAY_VERSION="$version"
  if [ -f "$XRAY_ENV_FILE" ]; then
    if ! sed -i "s/^export XRAY_VERSION=.*/export XRAY_VERSION=$(printf '%q' "$version")/" "$XRAY_ENV_FILE"; then
      err "Xray 已更新，但无法更新环境文件中的版本号"
      rm -f "$replacement"
      rm -rf "$update_dir"
      return 1
    fi
  fi
  if ! update_info; then
    err "Xray 已更新，但更新 xray_info.txt 失败"
    rm -f "$replacement"
    rm -rf "$update_dir"
    return 1
  fi
  if [ "$was_active" -eq 1 ]; then
    echo "[OK] Xray 已更新至 ${version} 并启动"
  else
    echo "[OK] Xray 已更新至 ${version}，服务保持停止"
  fi
  rm -f "$replacement"
  rm -rf "$update_dir"
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
import tempfile
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

def make_link(uuid, remark, flow, alpn):
    params = [("encryption", "none")]
    if flow:
        params.append(("flow", flow))
    params.extend([
        ("security", "tls"),
        ("type", "tcp"),
        ("sni", domain),
    ])
    if alpn:
        params.append(("alpn", alpn))
    return f"vless://{uuid}@{domain}:{port}?{urlencode(params)}#{quote(remark, safe='')}"

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

clients = clients_from(config)
tls_settings = config.get("inbounds", [{}])[0].get("streamSettings", {}).get("tlsSettings", {})
alpn = tls_settings.get("alpn", [])
if isinstance(alpn, list):
  alpn = ",".join(alpn)
elif not isinstance(alpn, str):
  alpn = ""
os.makedirs(os.path.dirname(info_file) or ".", exist_ok=True)

info_dir = os.path.dirname(info_file) or "."
fd, temp_path = tempfile.mkstemp(prefix=".xray_info.", dir=info_dir)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
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
            f.write(f"VLESS 链接: {make_link(uuid, remark, flow, alpn)}\n\n")
    os.chmod(temp_path, 0o600)
    os.replace(temp_path, info_file)
except Exception:
    try:
        os.unlink(temp_path)
    except FileNotFoundError:
        pass
    raise
PY
  chmod 600 "$INFO_FILE"
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

  finish_config_change "$backup" || return 1

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
  list_user
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

  finish_config_change "$backup" || return 1
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

def make_link(uuid, remark, flow, alpn):
    params = [("encryption", "none")]
    if flow:
        params.append(("flow", flow))
    params.extend([
        ("security", "tls"),
        ("type", "tcp"),
        ("sni", domain),
    ])
    if alpn:
        params.append(("alpn", alpn))
    return f"vless://{uuid}@{domain}:{port}?{urlencode(params)}#{quote(remark, safe='')}"

with open(config_file, "r", encoding="utf-8") as f:
    config = json.load(f)

clients = config.get("inbounds", [{}])[0].get("settings", {}).get("clients", [])
tls_settings = config.get("inbounds", [{}])[0].get("streamSettings", {}).get("tlsSettings", {})
alpn = tls_settings.get("alpn", [])
if isinstance(alpn, list):
  alpn = ",".join(alpn)
elif not isinstance(alpn, str):
  alpn = ""
if not clients:
    print("（暂无用户）")
    raise SystemExit(0)

for index, client in enumerate(clients, 1):
    remark = client.get("email", "未命名用户")
    uuid = client.get("id", "")
    flow = client.get("flow", default_flow)
    print(f"{index}. 备注: {remark}")
    print(f"   UUID: {uuid}")
    print(f"   链接: {make_link(uuid, remark, flow, alpn)}")
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
  if ! command -v systemctl >/dev/null 2>&1; then
    err "当前系统没有 systemctl，无法安全卸载服务"
    return 1
  fi
  if systemctl is-active --quiet "$SERVICE_NAME" && ! systemctl stop "$SERVICE_NAME"; then
    err "无法停止 Xray 服务，已取消卸载"
    return 1
  fi
  if systemctl is-enabled --quiet "$SERVICE_NAME" && ! systemctl disable "$SERVICE_NAME"; then
    err "无法禁用 Xray 服务，已取消卸载"
    return 1
  fi
  rm -f "$SERVICE_FILE" || return 1
  systemctl daemon-reload || {
    err "systemd 重新加载失败，已取消删除 Xray 文件"
    return 1
  }

  echo "==> 删除 Xray 文件"
  rm -rf -- "$XRAY_DIR" || return 1
  rm -f -- "$INFO_FILE" "$XRAY_ENV_FILE" "$XUSER_SCRIPT"

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
  echo "6) 关闭 Xray"
  echo "7) 显示 Xray 最近 100 条日志"
  echo "8) 重启 Xray"
  echo "9) 启动 Xray"
  echo "10) 更新 Xray 到最新版"
  echo "0) 退出"
  echo
}

while true; do
  show_menu
  read -r -p "请选择操作 [0-10]: " choice

  case "$choice" in
    1) add_user ;;
    2) del_user ;;
    3) list_user ;;
    4) update_info && echo "[OK] xray_info.txt 已更新" ;;
    5) uninstall ;;
    6) stop_xray ;;
    7) show_xray_logs ;;
    8) restart_xray && echo "[OK] Xray 已重启" ;;
    9) start_xray ;;
    10) update_xray_latest ;;
    0) echo "退出"; exit 0 ;;
    *) echo "[ERR] 无效选项" ;;
  esac
done
EOFXUSER
  } > "$XUSER_SCRIPT"

  chmod 0700 "$XUSER_SCRIPT"
}

echo "========== Xray VLESS 入口服务器自动部署脚本 =========="

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
detect_candidate_xray_version

log "生成 Xray 配置"
echo "    域名: $DOMAIN"
echo "    端口: $PORT"
echo "    出口节点: $UPSTREAM_ADDRESS:$UPSTREAM_PORT"
echo "    证书: $CERT_FILE"
echo "    私钥: $KEY_FILE"
echo "    Xray 目录: $XRAY_DIR"
write_xray_config
test_xray_config
if ! commit_xray_config; then
  rollback_deployment || err "自动回滚未能完整完成，请检查备份文件"
  die "写入 Xray 配置失败"
fi
if ! commit_xray_install; then
  rollback_deployment || err "自动回滚未能完整完成，请检查备份文件"
  die "安装 Xray 文件失败"
fi

log "写入 systemd 服务"
if ! write_systemd_service; then
  rollback_deployment || err "自动回滚未能完整完成，请检查备份文件"
  die "写入 systemd 服务失败"
fi
restart_service || die "Xray 服务启动失败"

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
