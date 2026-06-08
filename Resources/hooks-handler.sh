#!/usr/bin/env bash
# Claude Monitor - Hook Handler
# 由 Claude Code hooks 调用，将精确状态写入状态文件
# 状态文件路径: /tmp/claude-monitor/state-<session_id_prefix>.json

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','unknown')[:12])" 2>/dev/null || echo "unknown")
STATUS_DIR="/tmp/claude-monitor"
STATUS_FILE="$STATUS_DIR/state-$SESSION_ID.json"

mkdir -p "$STATUS_DIR"

# 将输入透传，附加 status 和时间戳
printf '%s' "$INPUT" | python3 -c "
import sys, json, time
data = json.load(sys.stdin)
data['status'] = sys.argv[1]
data['timestamp'] = int(time.time() * 1000)
json.dump(data, open(sys.argv[2], 'w'))
" "$1" "$STATUS_FILE" 2>/dev/null
