#!/usr/bin/env bash
# Claude Monitor - Hooks 安装脚本
# 将 hooks 配置注入 ~/.claude/settings.json
# 卸载: scripts/uninstall-hooks.sh

# 基于脚本所在位置推导 handler 绝对路径，避免硬编码本机路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDLER="$(cd "$SCRIPT_DIR/../Resources" && pwd)/hooks-handler.sh"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
    echo "❌ 未找到 $SETTINGS"
    exit 1
fi

if [ ! -f "$HANDLER" ]; then
    echo "❌ 未找到 hook handler: $HANDLER"
    echo "   请确认在仓库内运行本脚本。"
    exit 1
fi

echo "📦 正在安装 Claude Monitor hooks..."
echo "   handler: $HANDLER"

# 用 python3 安全地合并 hooks 到 settings.json
# 通过 argv 传参，避免路径中的特殊字符破坏脚本
python3 - "$HANDLER" "$SETTINGS" << 'PYEOF'
import json, sys

handler = sys.argv[1]
settings_path = sys.argv[2]

with open(settings_path, 'r') as f:
    settings = json.load(f)

hooks_config = {
    "PreToolUse": [
        {
            "matcher": "",
            "hooks": [{
                "type": "command",
                "command": f"{handler} tool_call",
                "timeout": 3
            }]
        }
    ],
    "Stop": [
        {
            "hooks": [{
                "type": "command",
                "command": f"{handler} stopped",
                "timeout": 5
            }]
        }
    ],
    "StopFailure": [
        {
            "hooks": [{
                "type": "command",
                "command": f"{handler} error",
                "timeout": 5
            }]
        }
    ],
    "Notification": [
        {
            "matcher": "permission_prompt",
            "hooks": [{
                "type": "command",
                "command": f"{handler} waiting_permission",
                "timeout": 3
            }]
        }
    ]
}

# 合并 hooks（不覆盖已有的）
if "hooks" not in settings:
    settings["hooks"] = hooks_config
else:
    existing = settings["hooks"]
    for event, configs in hooks_config.items():
        if event not in existing:
            existing[event] = configs
        else:
            # 检查是否已经安装过
            for cfg in configs:
                already_installed = False
                for existing_cfg in existing[event]:
                    for h in existing_cfg.get("hooks", []):
                        if "hooks-handler.sh" in h.get("command", ""):
                            already_installed = True
                            break
                    if already_installed:
                        break
                if not already_installed:
                    existing[event].append(cfg)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("✅ Hooks 已安装到", settings_path)
PYEOF

mkdir -p /tmp/claude-monitor
echo "✅ 状态目录已创建: /tmp/claude-monitor"
echo ""
echo "可用状态:"
echo "  🟠 tool_call        - Claude 正在调用工具"
echo "  🔴 waiting_permission - Claude 等待用户授权"
echo "  🟢 stopped          - Claude 完成响应"
echo "  ⚪ error            - 发生错误"
echo ""
echo "⚠️  需要重启 Claude Code 会话才能生效"
