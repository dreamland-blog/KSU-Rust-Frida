#!/system/bin/sh
# kfm-stealth.sh - 设置 rustfrida 隐写模式
# rustfrida 支持三种内存保护模式：
#   normal   - 标准 hook，直接修改代码页（默认）
#   wxshadow - 内核影子页，原始页面不变，hook 在影子页执行
#   recomp   - 代码重编译，整个函数重新生成，原地址不变
#
# 用法: kfm stealth [normal|wxshadow|recomp]

RUNTIME_DIR="/data/adb/kfm"
CONFIG_FILE="$RUNTIME_DIR/config.json"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

MODE="${1:-}"

if [ -z "$MODE" ]; then
    # 显示当前模式
    CURRENT="normal"
    if [ -f "$CONFIG_FILE" ]; then
        SM=$(grep -o '"stealth_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | sed 's/.*"\([^"]*\)"$/\1/')
        [ -n "$SM" ] && CURRENT="$SM"
    fi
    cat <<EOF
{
  "current_mode": "$CURRENT",
  "available": ["normal", "wxshadow", "recomp"],
  "description": {
    "normal": "Standard hooking, direct code page modification",
    "wxshadow": "Kernel shadow pages, original pages untouched",
    "recomp": "Code recompilation, function regeneration at original address"
  }
}
EOF
    exit 0
fi

# 验证模式值
case "$MODE" in
    normal|wxshadow|recomp) ;;
    *)
        json_error "invalid stealth mode: $MODE (use: normal, wxshadow, recomp)"
        exit 1
        ;;
esac

# 更新配置
if [ -f "$CONFIG_FILE" ]; then
    sed -i "s/\"stealth_mode\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"stealth_mode\": \"$MODE\"/" "$CONFIG_FILE"
else
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "{\"rustfrida\":{\"stealth_mode\":\"$MODE\"}}" > "$CONFIG_FILE"
fi

log_kfm "stealth: mode set to $MODE"
echo "{\"status\":\"ok\",\"stealth_mode\":\"$MODE\",\"note\":\"restart rustfrida to apply\"}"
