# deploy_xray
A simple project for automatically deploying Xray.
## 脚本版本对比

| 特性 | xray_vless.sh | xray_vless_plus.sh | xray_vless_pro.sh | xray_vless_plus_pro.sh | xray_vless_v2.sh |
|------|---|---|---|---|---|
| 核心部署 | Yes | Yes | Yes | Yes | Yes |
| xuser.sh 生成 | No | Yes | Yes | Yes | Yes |
| 初始用户标记 | - | No | Yes | Yes | Yes |
| Python3 JSON 支持 | - | No | Yes | Yes | Yes |
| Emoji 指示符 | Yes | Yes | Yes | Yes | No |
| 推荐使用 | - | - | - | - | Yes |

## 快速开始

### 推荐：使用 v2 版本（无 Emoji，优化消息）
```bash
bash xray_vless_v2.sh          # 核心部署 + 完整用户管理 + 优化消息 [推荐]
```

### 使用改进版本（带 Emoji）
```bash
bash xray_vless_pro.sh          # 核心部署 + 完整用户管理
# 或
bash xray_vless_plus_pro.sh     # 扩展版本（功能相同）
```

### 原始版本
```bash
bash xray_vless.sh              # 仅部署
bash xray_vless_plus.sh         # 部署 + 基础用户管理
```

## 版本说明

**xray_vless_v2.sh** - 最新推荐版本
- 基于 xray_vless_pro.sh 的优化版本
- 移除所有 Emoji 指示符
- 使用 [ERR]、[OK]、[WARN] 等文本标记
- 完整的多用户管理功能

**xray_vless_pro.sh / xray_vless_plus_pro.sh** - 改进版本
- 初始用户标记为"初始用户"
- Python3 JSON 安全修改（推荐）
- sed 降级方案（无 Python3 时）
- 更好的用户菜单界面
- 环境配置保存

**xray_vless.sh / xray_vless_plus.sh** - 原始版本
- 保留用于向后兼容
- 基础功能支持

## 改进版本优势

**xray_vless_v2.sh 特点：**
- 无 Emoji，兼容所有终端
- 文本标记清晰（[ERR]、[OK]、[WARN]）
- 初始用户自动标记
- Python3 JSON 安全处理
- sed 降级方案
- 更好的用户交互