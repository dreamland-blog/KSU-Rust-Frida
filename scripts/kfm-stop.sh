#!/system/bin/sh
# kfm-stop.sh - 停止 rustfrida 并清理

RUNTIME_DIR="/data/adb/kfm"
PID_FILE="$RUNTIME_DIR/run/rustfrida.pid"
RPC_PORT_FILE="$RUNTIME_DIR/run/rpc.port"

KILLED=0

# 1. 杀 PID 文件记录的进程
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        sleep 1
        # 还活着就强杀
        if kill -0 "$PID" 2>/dev/null; then
            kill -9 "$PID" 2>/dev/null
        fi
        KILLED=1
    fi
    rm -f "$PID_FILE"
fi

# 2. 兜底：按名字清理
for p in $(pgrep -f rustfrida 2>/dev/null); do
    kill -9 "$p" 2>/dev/null
    KILLED=1
done

# 3. 清理状态文件和 FIFO 控制进程
if [ -f "$RUNTIME_DIR/run/rustfrida_fifo.pid" ]; then
    FIFO_PID=$(cat "$RUNTIME_DIR/run/rustfrida_fifo.pid")
    [ -n "$FIFO_PID" ] && kill "$FIFO_PID" 2>/dev/null
    rm -f "$RUNTIME_DIR/run/rustfrida_fifo.pid"
fi
rm -f "$RUNTIME_DIR/run/rustfrida.fifo"
rm -f "$RPC_PORT_FILE"

echo "{\"status\":\"ok\",\"killed\":$KILLED}"
