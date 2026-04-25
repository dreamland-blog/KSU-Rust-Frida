#!/system/bin/sh
# common.sh - KFM 公共函数库
# 所有子脚本 source 此文件

RUNTIME_DIR="/data/adb/kfm"
MODULE_DIR="/data/adb/modules/ksu-frida-manager"
KFM_LOG="$RUNTIME_DIR/logs/kfm.log"

# rustfrida 二进制路径：优先 /system/bin（overlay），fallback 模块目录
if [ -x "/system/bin/rustfrida" ]; then
    RUSTFRIDA_BIN="/system/bin/rustfrida"
else
    RUSTFRIDA_BIN="$MODULE_DIR/system/bin/rustfrida"
fi

# JSON 错误输出
json_error() {
    echo "{\"error\":\"$1\"}"
}

# JSON 成功输出
json_ok() {
    echo "{\"status\":\"ok\"$1}"
}

# 写 KFM 日志
log_kfm() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$KFM_LOG" 2>/dev/null
}

# 从 JSON 文件读取字段值（简易实现，仅支持一级字段）
read_json_field() {
    _FILE="$1"
    _FIELD="$2"
    grep -o "\"$_FIELD\"[[:space:]]*:[[:space:]]*[\"0-9][^,}]*" "$_FILE" 2>/dev/null | \
        head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"'
}

# 检查 rustfrida 是否在运行
is_rustfrida_running() {
    PID_FILE="$RUNTIME_DIR/run/rustfrida.pid"
    if [ -f "$PID_FILE" ]; then
        _PID=$(cat "$PID_FILE")
        if [ -n "$_PID" ] && kill -0 "$_PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# 获取 rustfrida PID
get_rustfrida_pid() {
    PID_FILE="$RUNTIME_DIR/run/rustfrida.pid"
    [ -f "$PID_FILE" ] && cat "$PID_FILE" 2>/dev/null
}

# 获取 RPC 端口
get_rpc_port() {
    RPC_PORT_FILE="$RUNTIME_DIR/run/rpc.port"
    [ -f "$RPC_PORT_FILE" ] && cat "$RPC_PORT_FILE" 2>/dev/null
}

# 检查是否处于分析模式
is_analyze_mode() {
    [ -f "$RUNTIME_DIR/run/analyze-mode.lock" ]
}

# 查找 App PID（兼容多种 Android 版本）
find_app_pid() {
    _PKG="$1"
    # 方法1: pidof
    _PID=$(pidof "$_PKG" 2>/dev/null | awk '{print $1}')
    [ -n "$_PID" ] && echo "$_PID" && return

    # 方法2: pgrep
    _PID=$(pgrep -f "^$_PKG$" 2>/dev/null | head -1)
    [ -n "$_PID" ] && echo "$_PID" && return

    # 方法3: ps + grep
    _PID=$(ps -eo pid,args 2>/dev/null | grep "$_PKG" | grep -v grep | awk '{print $1}' | head -1)
    [ -n "$_PID" ] && echo "$_PID"
}
