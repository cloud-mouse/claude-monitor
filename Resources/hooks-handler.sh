#!/usr/bin/env bash
# Claude Monitor - Hook Handler
# 由 Claude Code hooks 调用，将精确状态写入状态文件
# 状态文件路径: /tmp/claude-monitor/state-<session_id_prefix>.json

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','unknown')[:12])" 2>/dev/null || echo "unknown")
STATUS_DIR="/tmp/claude-monitor"
STATUS_FILE="$STATUS_DIR/state-$SESSION_ID.json"

# 确定 actual status：
# PreToolUse 时如果工具是 AskUserQuestion → waiting_input（等待用户回答问题）
ACTUAL_STATUS="$1"
if [ "$ACTUAL_STATUS" = "tool_call" ]; then
    TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
    case "$TOOL_NAME" in
        AskUserQuestion)
            ACTUAL_STATUS="waiting_input"
            ;;
    esac
fi

mkdir -p "$STATUS_DIR"

# 将输入透传，附加 status 和时间戳
printf '%s' "$INPUT" | python3 -c "
import sys, json, time
data = json.load(sys.stdin)
data['status'] = sys.argv[1]
data['timestamp'] = int(time.time() * 1000)
json.dump(data, open(sys.argv[2], 'w'))
" "$ACTUAL_STATUS" "$STATUS_FILE" 2>/dev/null
