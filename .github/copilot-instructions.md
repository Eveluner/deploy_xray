# Xray Deployment AI Coding Agent Instructions

## Project Overview
**deploy_xray** is an automated bash-based deployment toolkit for setting up Xray VLESS protocol servers with TLS security. The project provides multiple script variants:
- `xray_vless.sh`: Original core deployment automation
- `xray_vless_plus.sh`: Extended version with built-in user management script generation
- `xray_vless_pro.sh`: **Enhanced** version with improved xuser.sh implementation (multi-user management with robust JSON parsing)
- `xray_vless_plus_pro.sh`: Enhanced extended version combining plus features with pro improvements

## Architecture & Core Concepts

### Deployment Workflow (6-7 Steps)
1. **Environment Detection**: Verify systemd availability and install dependencies (curl, unzip)
2. **Xray Acquisition**: Three options—recommended v26.1.23 from GitHub, custom URL, or local file
3. **Installation**: Extract to user-specified directory (default: `/root/xray`)
4. **UUID Generation**: Auto-generate client ID via `xray uuid` command
5. **Configuration Generation**: Create JSON config with VLESS inbound, TLS settings, and freedom outbound
6. **Service Setup**: Configure systemd service for auto-start with restart policies
7. **Link Generation** (plus only): Create VLESS connection link; generate `xuser.sh` for multi-user management

### Critical Implementation Details
- **Configuration File**: `/root/xray/config.json` contains the complete VLESS protocol configuration
- **VLESS Protocol Stack**: Uses `xtls-rprx-vision` flow with TLS 1.3, specific cipher suites (TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384)
- **Multi-User Support**: The `xuser.sh` helper script manages additional users via `clients` array mutations (sed-based insertion/deletion)
- **Connection Format**: `vless://UUID@DOMAIN:PORT?encryption=none&flow=xtls-rprx-vision&security=tls&type=tcp&sni=DOMAIN`
- **Default Ports & Paths**: Port is user-specified; default installation path `/root/xray`; info saved to `/root/xray_info.txt`

## Key Development Patterns & Conventions

### Bash Script Standards
- **Error Handling**: `set -e` at script start ensures immediate exit on any command failure (no error silencing)
- **Package Manager Abstraction**: `install_pkg()` function provides apt/yum compatibility for different Linux distributions
- **Command Detection**: Use `command -v <pkg>` to check availability (more portable than `which`)
- **Heredoc Configuration**: Multiline JSON/service configs embedded via heredoc syntax with variable substitution

### User Input & Defaults
- Always provide default values in square brackets: `read -p "prompt [default]: "`
- Use variable substitution pattern: `VAR=${VAR:-default_value}`
- For sensitive paths (certificates, keys), request full paths without assuming locations

### Configuration Generation
- Generate JSON configs via heredoc templates (not external file imports)
- Variable substitution inside heredoc: use unquoted heredoc syntax (`<< EOF`) for shell expansion
- Embed version strings explicitly (e.g., `"Xray 版本: 26.1.23"`) rather than dynamic lookup

### Xray Command Patterns
- **Version Check**: `$XRAY_DIR/xray version` confirms successful installation
- **Config Validation**: `$XRAY_DIR/xray run -test -config $CONFIG_FILE` validates syntax before service start
- **UUID Generation**: `$UUID=$($XRAY_DIR/xray uuid)` for automatic client ID creation

### User Management (xuser.sh specifics)
- **State Storage**: User metadata stored in `xray_info.txt` alongside JSON config (dual-source design)
- **Initial User**: First client automatically gets `"email": "初始用户"` field for tracking
- **Config Mutations**: Add users via `sed -i` insertion after `"clients": [` marker; delete via JSON parsing (python3) or sed pattern matching
- **Info Sync**: `update_info()` reconstructs `xray_info.txt` by parsing `config.json` with awk, displaying all users with UUIDs and VLESS links
- **Email Field**: User remarks stored in `"email"` field within client objects (non-standard but effective for tracking)
- **Multi-Tool Support**: Uses python3-based JSON manipulation for safe deletion (graceful fallback to sed if python3 unavailable)
- **Menu-Driven Interface**: Interactive loop with options: add user (1), delete user (2), list users (3), update info (4), uninstall (5), exit (0)

## Integration Points & Dependencies

### External Services
- **GitHub Releases API**: Downloads Xray v26.1.23 from `https://github.com/XTLS/Xray-core/releases/download/v26.1.23/Xray-linux-64.zip`
- **systemd**: Required for service management (hard dependency; exit if unavailable)
- **TLS Certificates**: External certificates/keys provided by user at runtime

### System Requirements
- Linux with systemd support (Ubuntu 20.04+, CentOS 8+, etc.)
- Root/sudo privileges for systemd service installation
- Internet access for package installation and Xray binary download

## Common Workflows & Commands

### Using Original Scripts
```bash
bash xray_vless.sh
# Minimal deployment without xuser.sh generation

bash xray_vless_plus.sh
# Deployment with basic xuser.sh generation
```

### Using Pro (Enhanced) Scripts - RECOMMENDED
```bash
bash xray_vless_pro.sh
# Enhanced core deployment with improved xuser.sh
# Features: robust JSON parsing, better error handling, initial user tracking

bash xray_vless_plus_pro.sh
# Enhanced extended deployment (preferred variant)
# Same improvements as xray_vless_pro.sh
```

### Key Improvements in Pro Versions
- Initial user marked with `"email": "初始用户"` in config.json
- `xuser.sh` uses python3 with sed fallback for safe JSON mutations
- Better error handling and config validation
- Improved menu UI with emoji indicators
- Environment variables saved to `/root/.xray_env`
- xray_info.txt formatted with user-friendly VLESS connection display

## Testing & Validation Recommendations
- Test config syntax immediately after generation: `xray run -test -config config.json`
- Verify service startup: `systemctl status xray` (should show `active (running)`)
- Generate test VLESS links and validate link format matches: `vless://UUID@DOMAIN:PORT?...`
- For modifications to `xuser.sh`, test sed patterns against sample config.json to avoid accidental deletions

## Edge Cases & Debugging
- **Package Manager Failure**: Scripts exit if neither apt nor yum found; add new managers to `install_pkg()` if needed
- **Sed Special Characters**: UUID/email values in `xuser.sh` could break sed patterns if they contain `/` or `&`; consider escaping or using `sed -i.bak` for safety
- **Service Restart Timing**: Systemd restart immediately after config mutation; ensure config is valid before triggering `systemctl restart xray`
- **Duplicate Clients**: `add_user()` appends without deduplication; check for UUID collisions in `list_user()`

## Files to Modify When Extending
- `xray_vless.sh`: Original core logic (no xuser.sh)
- `xray_vless_plus.sh`: Original extended version with basic xuser.sh
- `xray_vless_pro.sh`: **RECOMMENDED** enhanced core—modify configuration template or service parameters here
- `xray_vless_plus_pro.sh`: **RECOMMENDED** enhanced extended version combining plus features with pro improvements
- User management: Edit the embedded `xuser.sh` heredoc (lines ~195-435 in `xray_vless_pro.sh`) to add new operations (e.g., user suspension, bandwidth limiting)
