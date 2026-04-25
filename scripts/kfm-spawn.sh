#!/system/bin/sh
# kfm-spawn.sh - 通过 zymbiote 劫持 zygote 实现 spawn 注入
# rustfrida 独有功能：从 App 启动第一行代码就开始 hook
#
# 用法: kfm spawn <package> [script1.js] [script2.js] ...

RUNTIME_DIR="/data/adb/kfm"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

PACKAGE="$1"
shift 2>/dev/null || true

if [ -z "$PACKAGE" ]; then
    json_error "usage: kfm spawn <package> [script1.js ...]"
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

log_kfm "spawn: launching $PACKAGE with zymbiote hook"

# 使用 rustfrida 的 spawn 模式
SPAWN_ARGS="--spawn $PACKAGE"

if [ "$SCRIPT_COUNT" -eq 1 ]; then
    FINAL_SCRIPT=$(echo "$SCRIPTS" | xargs)
    SPAWN_ARGS="$SPAWN_ARGS --load-script $FINAL_SCRIPT"
elif [ "$SCRIPT_COUNT" -gt 1 ]; then
    FINAL_SCRIPT="$RUNTIME_DIR/run/_combined.js"
    rm -f "$FINAL_SCRIPT"
    for s in $SCRIPTS; do
        echo "// ===== $(basename $s) =====" >> "$FINAL_SCRIPT"
        cat "$s" >> "$FINAL_SCRIPT"
        echo "" >> "$FINAL_SCRIPT"
    done
    log_kfm "spawn: combined $SCRIPT_COUNT scripts into $FINAL_SCRIPT"
    SPAWN_ARGS="$SPAWN_ARGS --load-script $FINAL_SCRIPT"
fi

exec "$RUSTFRIDA_BIN" $SPAWN_ARGS 2>&1
