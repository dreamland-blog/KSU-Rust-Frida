#!/system/bin/sh
# kfm-log.sh - 查看日志

RUNTIME_DIR="/data/adb/kfm"

TARGET="${1:-kfm}"

case "$TARGET" in
    server|rustfrida)
        LOG_FILE="$RUNTIME_DIR/logs/rustfrida.log"
        ;;
    kfm|*)
        LOG_FILE="$RUNTIME_DIR/logs/kfm.log"
        ;;
esac

if [ ! -f "$LOG_FILE" ]; then
    echo "{\"status\":\"no_log\",\"file\":\"$LOG_FILE\"}"
    exit 0
fi

# 如果有 -f 参数就 tail -f，否则输出最后 50 行
if [ "$2" = "-f" ]; then
    tail -f "$LOG_FILE"
else
    tail -50 "$LOG_FILE"
fi
