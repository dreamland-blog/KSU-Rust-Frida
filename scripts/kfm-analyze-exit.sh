#!/system/bin/sh
# kfm-analyze-exit.sh - 退出分析模式，恢复模块并重启

RUNTIME_DIR="/data/adb/kfm"
LOCK_FILE="$RUNTIME_DIR/run/analyze-mode.lock"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

if [ ! -f "$LOCK_FILE" ]; then
    echo '{"status":"not_in_analyze_mode"}'
    exit 0
fi

# 从 lock 文件读取被禁用的模块
DISABLED=$(grep '"disabled_modules"' "$LOCK_FILE" | sed 's/.*"disabled_modules":[[:space:]]*"\([^"]*\)".*/\1/')

# 恢复每个模块
for mod in $DISABLED; do
    rm -f "/data/adb/modules/$mod/disable"
    log_kfm "analyze: restored module $mod"
done

# 确保 rustfrida 停止
sh /data/adb/modules/ksu-frida-manager/scripts/kfm-stop.sh >/dev/null 2>&1

# 删除 lock
rm -f "$LOCK_FILE"

log_kfm "analyze: exited analysis mode, restored:$DISABLED"
echo "{\"status\":\"ok\",\"restored\":\"$DISABLED\",\"action\":\"rebooting in 5s\"}"

# 5 秒后重启
(sleep 5 && /system/bin/svc power reboot) &
