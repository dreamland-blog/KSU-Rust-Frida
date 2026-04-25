#!/system/bin/sh
# kfm-inject.sh - 对运行中的 App 做注入（attach 模式）
# 使用 rustfrida --pid 进行进程注入
#
# 用法: kfm inject <package> <script1.js> [script2.js] [script3.js] ...
#   多个脚本会自动合并为一个临时文件注入

RUNTIME_DIR="/data/adb/kfm"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

PACKAGE="$1"
shift 2>/dev/null || true

if [ -z "$PACKAGE" ] || [ -z "$1" ]; then
    json_error "usage: kfm inject <package> <script1.js> [script2.js ...]"
    exit 1
fi

# 脚本路径解析函数
resolve_script() {
    local s="$1"
    if [ -f "$s" ]; then
        echo "$s"
    elif [ -f "$RUNTIME_DIR/scripts/$s" ]; then
        echo "$RUNTIME_DIR/scripts/$s"
    elif [ -f "$RUNTIME_DIR/scripts/${s}.js" ]; then
        echo "$RUNTIME_DIR/scripts/${s}.js"
    else
        echo ""
    fi
}

# 收集所有脚本
SCRIPTS=""
SCRIPT_COUNT=0
for arg in "$@"; do
    resolved=$(resolve_script "$arg")
    if [ -z "$resolved" ]; then
        json_error "script not found: $arg"
        exit 2
    fi
    SCRIPTS="$SCRIPTS $resolved"
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
done

# 如果只有一个脚本, 直接用; 多个则合并
if [ "$SCRIPT_COUNT" -eq 1 ]; then
    FINAL_SCRIPT=$(echo "$SCRIPTS" | xargs)
else
    FINAL_SCRIPT="$RUNTIME_DIR/run/_combined.js"
    rm -f "$FINAL_SCRIPT"
    for s in $SCRIPTS; do
        echo "// ===== $(basename $s) =====" >> "$FINAL_SCRIPT"
        cat "$s" >> "$FINAL_SCRIPT"
        echo "" >> "$FINAL_SCRIPT"
    done
    log_kfm "inject: combined $SCRIPT_COUNT scripts into $FINAL_SCRIPT"
fi

# 查找目标 App 的 PID
TARGET_PID=$(pidof "$PACKAGE" 2>/dev/null | awk '{print $1}')

if [ -z "$TARGET_PID" ]; then
    # 尝试启动 App
    am start -n "$(cmd package resolve-activity --brief "$PACKAGE" 2>/dev/null | tail -1)" >/dev/null 2>&1 || \
    monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 2
    TARGET_PID=$(pidof "$PACKAGE" 2>/dev/null | awk '{print $1}')
fi

if [ -z "$TARGET_PID" ]; then
    json_error "target app not running: $PACKAGE"
    exit 3
fi

log_kfm "inject: attaching to $PACKAGE (PID $TARGET_PID) with $SCRIPT_COUNT script(s)"

# 使用 rustfrida 的 PID 注入模式
exec "$RUSTFRIDA_BIN" --pid "$TARGET_PID" --load-script "$FINAL_SCRIPT" 2>&1
