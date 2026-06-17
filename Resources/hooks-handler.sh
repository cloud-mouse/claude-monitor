#!/usr/bin/env bash
# Claude Monitor - Hook Handler
# 由 Claude Code hooks 调用，将精确状态写入状态文件
# 状态文件路径: /tmp/claude-monitor/state-<session_id_prefix>.json
#
# 用法: hooks-handler.sh <status>
#   <status> ∈ tool_call | stopped | error | waiting_permission
#   stdin:  Claude Code 传入的事件 JSON

ACTUAL_STATUS="${1:-}"
STATUS_DIR="/tmp/claude-monitor"

# 先缓存 stdin（hook 事件 JSON），再喂给 python；单次 python 进程完成全部工作
INPUT="$(cat)"

printf '%s' "$INPUT" | python3 -c '
import sys, json, time, os
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

status = sys.argv[1]
# PreToolUse 时如果工具是 AskUserQuestion → waiting_input（等待用户回答问题）
if status == "tool_call" and data.get("tool_name") == "AskUserQuestion":
    status = "waiting_input"

session_id = str(data.get("session_id", "unknown"))[:12]
data["status"] = status
data["timestamp"] = int(time.time() * 1000)

out_dir = sys.argv[2]
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "state-" + session_id + ".json"), "w") as f:
    json.dump(data, f)
' "$ACTUAL_STATUS" "$STATUS_DIR" 2>/dev/null
