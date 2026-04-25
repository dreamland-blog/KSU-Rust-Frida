#!/system/bin/sh
# kfm-watch.sh - 等待指定 SO 加载后自动注入
# 利用 rustfrida 的 ldmonitor (eBPF) 功能
#
# 用法: kfm watch <so_name> <script.js>
# 例如: kfm watch libnative.so hook.js

RUNTIME_DIR="/data/adb/kfm"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

SO_NAME="$1"
SCRIPT="$2"

if [ -z "$SO_NAME" ] || [ -z "$SCRIPT" ]; then
    json_error "usage: kfm watch <so_name> <script.js>"
    exit 1
fi

# 脚本路径解析
if [ ! -f "$SCRIPT" ]; then
    if [ -f "$RUNTIME_DIR/scripts/$SCRIPT" ]; then
        SCRIPT="$RUNTIME_DIR/scripts/$SCRIPT"
    elif [ -f "$RUNTIME_DIR/scripts/${SCRIPT}.js" ]; then
        SCRIPT="$RUNTIME_DIR/scripts/${SCRIPT}.js"
    else
        json_error "script not found: $SCRIPT"
        exit 2
    fi
fi

log_kfm "watch: waiting for $SO_NAME to load, will inject $SCRIPT"

# --watch-so: 使用 eBPF (ldmonitor) 监控 dlopen
# 当目标进程加载指定 SO 时自动注入
exec "$RUSTFRIDA_BIN" --watch-so "$SO_NAME" --load-script "$SCRIPT" 2>&1
