#!/system/bin/sh
# kfm-analyze-enter.sh - 进入分析模式
# 1. 备份当前启用的模块列表
# 2. 禁用所有冲突模块（zygisk、PIF 等）
# 3. 写入 lock 文件
# 4. 重启手机
#
# 分析模式下 zygote 无其他 hook 干扰，rustfrida 可安全使用所有功能

RUNTIME_DIR="/data/adb/kfm"
LOCK_FILE="$RUNTIME_DIR/run/analyze-mode.lock"
CONFIG_FILE="$RUNTIME_DIR/config.json"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

# 已经在分析模式？
if [ -f "$LOCK_FILE" ]; then
    echo '{"status":"already_in_analyze_mode"}'
    exit 0
fi

# 从配置读取冲突模块列表，如果没有配置则使用默认
CONFLICT_MODULES="zygisksu zygisk_vector playintegrityfix pifs_cleverestech YH_YC"
if [ -f "$CONFIG_FILE" ]; then
    # 尝试从 JSON 数组中提取模块名
    CUSTOM=$(grep -o '"conflict_modules"[[:space:]]*:.*\]' "$CONFIG_FILE" 2>/dev/null | \
             grep -o '"[a-zA-Z_]*"' | tr -d '"' | tr '\n' ' ')
    [ -n "$CUSTOM" ] && CONFLICT_MODULES="$CUSTOM"
fi

# 备份当前状态并禁用冲突模块
BACKUP_LIST=""
for mod in $CONFLICT_MODULES; do
    MOD_PATH="/data/adb/modules/$mod"
    if [ -d "$MOD_PATH" ] && [ ! -f "$MOD_PATH/disable" ]; then
        touch "$MOD_PATH/disable"
        BACKUP_LIST="$BACKUP_LIST $mod"
        log_kfm "analyze: disabled module $mod"
    fi
done

# 写 lock 文件（记录哪些模块被禁用，退出时要恢复）
cat > "$LOCK_FILE" <<EOF
{
  "entered_at": "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)",
  "disabled_modules": "$BACKUP_LIST"
}
EOF

log_kfm "analyze: entered analysis mode, disabled:$BACKUP_LIST"
echo "{\"status\":\"ok\",\"disabled\":\"$BACKUP_LIST\",\"action\":\"rebooting in 5s\"}"

# 5 秒后重启
(sleep 5 && /system/bin/svc power reboot) &
