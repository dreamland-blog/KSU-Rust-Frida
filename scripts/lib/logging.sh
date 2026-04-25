#!/system/bin/sh
# logging.sh - 日志工具函数

RUNTIME_DIR="/data/adb/kfm"
KFM_LOG="$RUNTIME_DIR/logs/kfm.log"
MAX_LOG_SIZE=1048576  # 1MB

# 带级别的日志
log_info()  { _log "INFO"  "$1"; }
log_warn()  { _log "WARN"  "$1"; }
log_error() { _log "ERROR" "$1"; }
log_debug() { _log "DEBUG" "$1"; }

_log() {
    _LEVEL="$1"
    _MSG="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$_LEVEL] $_MSG" >> "$KFM_LOG" 2>/dev/null
}

# 日志轮转：超过 MAX_LOG_SIZE 时截断保留最后 500 行
rotate_log() {
    _FILE="${1:-$KFM_LOG}"
    if [ -f "$_FILE" ]; then
        _SIZE=$(wc -c < "$_FILE" 2>/dev/null)
        if [ "$_SIZE" -gt "$MAX_LOG_SIZE" ] 2>/dev/null; then
            tail -500 "$_FILE" > "${_FILE}.tmp"
            mv "${_FILE}.tmp" "$_FILE"
        fi
    fi
}
