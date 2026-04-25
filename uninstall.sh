#!/system/bin/sh
# uninstall.sh - 模块卸载时执行

# 停止 rustfrida
pkill -9 -f rustfrida 2>/dev/null

# 检查是否处于分析模式，如果是则恢复模块
LOCK_FILE="/data/adb/kfm/run/analyze-mode.lock"
if [ -f "$LOCK_FILE" ]; then
    DISABLED=$(grep '"disabled_modules"' "$LOCK_FILE" | sed 's/.*"disabled_modules":"\([^"]*\)".*/\1/')
    for mod in $DISABLED; do
        rm -f "/data/adb/modules/$mod/disable"
    done
fi

# 清理 runtime 目录
rm -rf /data/adb/kfm
