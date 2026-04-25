#!/system/bin/sh
# kfm-status.sh - 查询当前状态（JSON 输出）

RUNTIME_DIR="/data/adb/kfm"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

PID_FILE="$RUNTIME_DIR/run/rustfrida.pid"
RPC_PORT_FILE="$RUNTIME_DIR/run/rpc.port"
ANALYZE_LOCK="$RUNTIME_DIR/run/analyze-mode.lock"

# rustfrida 服务状态
SERVER_RUNNING="false"
SERVER_PID="null"
RPC_PORT="null"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        SERVER_RUNNING="true"
        SERVER_PID="$PID"
    fi
fi

if [ -f "$RPC_PORT_FILE" ] && [ "$SERVER_RUNNING" = "true" ]; then
    RPC_PORT=$(cat "$RPC_PORT_FILE")
fi

# 分析模式状态
ANALYZE_MODE="normal"
if [ -f "$ANALYZE_LOCK" ]; then
    ANALYZE_MODE="analysis"
fi

# rustfrida 版本
RUSTFRIDA_VER=$("$RUSTFRIDA_BIN" --version 2>/dev/null | head -1)
[ -z "$RUSTFRIDA_VER" ] && RUSTFRIDA_VER="unknown"

# 隐写模式
STEALTH_MODE="normal"
if [ -f "$RUNTIME_DIR/config.json" ]; then
    SM=$(grep -o '"stealth_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$RUNTIME_DIR/config.json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
    [ -n "$SM" ] && STEALTH_MODE="$SM"
fi

# 活跃 session 数（通过 RPC 查询）
SESSIONS="null"
if [ "$SERVER_RUNNING" = "true" ] && [ "$RPC_PORT" != "null" ]; then
    SESSIONS=$(wget -qO- "http://127.0.0.1:$RPC_PORT/sessions" 2>/dev/null | grep -c '"pid"' || echo "0")
fi

cat <<EOF
{
  "server": {
    "running": $SERVER_RUNNING,
    "pid": $SERVER_PID,
    "rpc_port": $RPC_PORT,
    "engine": "rustfrida"
  },
  "stealth_mode": "$STEALTH_MODE",
  "analyze_mode": "$ANALYZE_MODE",
  "active_sessions": $SESSIONS,
  "rustfrida_version": "$RUSTFRIDA_VER",
  "module_version": "v2.0.0",
  "uptime": $(cut -d. -f1 /proc/uptime)
}
EOF
