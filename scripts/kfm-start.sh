#!/system/bin/sh
# kfm-start.sh - 启动 rustfrida 服务
# 核心逻辑：延迟启动 + 冲突检测 + RPC 服务

RUNTIME_DIR="/data/adb/kfm"
PID_FILE="$RUNTIME_DIR/run/rustfrida.pid"
RPC_PORT_FILE="$RUNTIME_DIR/run/rpc.port"
LOG_FILE="$RUNTIME_DIR/logs/rustfrida.log"
CONFIG_FILE="$RUNTIME_DIR/config.json"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

# 解析参数
RPC_PORT=""
STEALTH_MODE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --rpc-port) RPC_PORT="$2"; shift 2 ;;
        --stealth)  STEALTH_MODE="$2"; shift 2 ;;
        *)          RPC_PORT="$1"; shift ;;
    esac
done

# 从配置读取默认值
if [ -z "$RPC_PORT" ] && [ -f "$CONFIG_FILE" ]; then
    RPC_PORT=$(read_json_field "$CONFIG_FILE" "rpc_port")
fi
RPC_PORT="${RPC_PORT:-28042}"

if [ -z "$STEALTH_MODE" ] && [ -f "$CONFIG_FILE" ]; then
    STEALTH_MODE=$(read_json_field "$CONFIG_FILE" "stealth_mode")
fi
STEALTH_MODE="${STEALTH_MODE:-normal}"

# 1. 已经在运行？
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "{\"status\":\"already_running\",\"pid\":$OLD_PID,\"rpc_port\":$RPC_PORT}"
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# 2. 检查系统启动时间（避开开机阶段）
UPTIME=$(cut -d. -f1 /proc/uptime)
MIN_UPTIME=30
if [ -f "$CONFIG_FILE" ]; then
    CFG_MIN=$(read_json_field "$CONFIG_FILE" "min_uptime_seconds")
    [ -n "$CFG_MIN" ] && MIN_UPTIME="$CFG_MIN"
fi
if [ "$UPTIME" -lt "$MIN_UPTIME" ]; then
    REMAIN=$((MIN_UPTIME - UPTIME))
    echo "{\"status\":\"error\",\"reason\":\"system too young, wait ${REMAIN}s more\"}"
    exit 2
fi

# 3. 检查 rustfrida 二进制
if [ ! -x "$RUSTFRIDA_BIN" ]; then
    echo "{\"status\":\"error\",\"reason\":\"rustfrida binary not found at $RUSTFRIDA_BIN\"}"
    exit 3
fi

# 4. 检查冲突模块（只警告不阻止）
WARNINGS=""
for mod in zygisksu zygisk_vector; do
    if [ -d "/data/adb/modules/$mod" ] && [ ! -f "/data/adb/modules/$mod/disable" ]; then
        WARNINGS="$WARNINGS $mod"
    fi
done

# 5. 延迟启动（给 zygote 更多稳定时间）
DELAY=3
if [ -f "$CONFIG_FILE" ]; then
    CFG_DELAY=$(read_json_field "$CONFIG_FILE" "startup_delay_seconds")
    [ -n "$CFG_DELAY" ] && DELAY="$CFG_DELAY"
fi
sleep "$DELAY"

# 6. 启动 rustfrida --server 模式
# --server: 多 session 模式，监听 RPC 端口
# --rpc-port: HTTP RPC 端口，供 App 直连
RUSTFRIDA_ARGS="--server --rpc-port $RPC_PORT"

# 注：stealth 模式通过 RPC/REPL 在运行时设置，不是 CLI 启动参数

FIFO_FILE="$RUNTIME_DIR/run/rustfrida.fifo"
rm -f "$FIFO_FILE"
mkfifo "$FIFO_FILE"
# 启动一个无限睡眠的进程来保持 FIFO 端写打开，防止 rustfrida 的 rustyline 读到 EOF 退
sleep 2147483647 > "$FIFO_FILE" &
SLEEP_PID=$!
echo "$SLEEP_PID" > "$RUNTIME_DIR/run/rustfrida_fifo.pid"

nohup "$RUSTFRIDA_BIN" $RUSTFRIDA_ARGS < "$FIFO_FILE" > "$LOG_FILE" 2>&1 &
NEW_PID=$!

# 7. 等待确认启动成功
sleep 2
if ! kill -0 "$NEW_PID" 2>/dev/null; then
    LAST_LOG=$(tail -5 "$LOG_FILE" 2>/dev/null | tr '\n' ' ')
    echo "{\"status\":\"error\",\"reason\":\"rustfrida died within 2s\",\"log\":\"$LAST_LOG\"}"
    exit 4
fi

# 8. 写状态文件
echo "$NEW_PID" > "$PID_FILE"
echo "$RPC_PORT" > "$RPC_PORT_FILE"

# 9. 返回结果
WARN_STR=""
[ -n "$WARNINGS" ] && WARN_STR=",\"warnings\":\"$WARNINGS\""
echo "{\"status\":\"ok\",\"pid\":$NEW_PID,\"rpc_port\":$RPC_PORT,\"stealth\":\"$STEALTH_MODE\"$WARN_STR}"
