#!/usr/bin/env bash
# Claude Monitor - Hooks 卸载脚本
# 从 ~/.claude/settings.json 移除本工具注入的 hooks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDLER="$(cd "$SCRIPT_DIR/../Resources" && pwd)/hooks-handler.sh"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
    echo "❌ 未找到 $SETTINGS"
    exit 1
fi

echo "📦 正在卸载 Claude Monitor hooks..."

python3 - "$SETTINGS" "$HANDLER" << 'PYEOF'
import json, shlex, sys

path = sys.argv[1]
handler = sys.argv[2]
quoted_handler = shlex.quote(handler)

def is_own_command(command):
    return command.startswith(handler + " ") or command.startswith(quoted_handler + " ")

with open(path, 'r') as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
removed = 0

for event in list(hooks.keys()):
    new_configs = []
    for cfg in hooks[event]:
        hook_list = cfg.get("hooks", [])
        kept = [h for h in hook_list if not is_own_command(h.get("command", ""))]
        removed += len(hook_list) - len(kept)
        if kept:
            cfg["hooks"] = kept
            new_configs.append(cfg)
    if new_configs:
        hooks[event] = new_configs
    else:
        del hooks[event]

if hooks:
    settings["hooks"] = hooks
elif "hooks" in settings:
    del settings["hooks"]

with open(path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print(f"✅ 已移除 {removed} 个 Claude Monitor hook（{path}）")
PYEOF

echo "⚠️  需要重启 Claude Code 会话才能生效"
