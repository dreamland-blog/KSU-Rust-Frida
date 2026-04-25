#!/sbin/sh
# customize.sh - 模块刷入时执行
# 整合 rustFrida 引擎的 KSU-Frida Manager

SKIPUNZIP=0

# 检查 Android 版本
API=$(getprop ro.build.version.sdk)
if [ "$API" -lt 28 ]; then
    ui_print "! Android 9+ required (current: API $API)"
    abort
fi

# 检查架构 - rustfrida 仅支持 arm64
ARCH=$(getprop ro.product.cpu.abi)
if [ "$ARCH" != "arm64-v8a" ]; then
    ui_print "! arm64-v8a required (current: $ARCH)"
    ui_print "! rustFrida only supports ARM64"
    abort
fi

ui_print ""
ui_print "============================================"
ui_print " KSU-Frida Manager v2.0.0"
ui_print " Powered by rustFrida Engine"
ui_print "============================================"
ui_print ""
ui_print "- Device: $(getprop ro.product.model)"
ui_print "- Android: API $API ($ARCH)"
ui_print "- Kernel: $(uname -r)"
ui_print ""

# 设置权限
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/system/bin/kfm 0 0 0755
set_perm $MODPATH/system/bin/rustfrida 0 0 0755
chmod -R 0755 $MODPATH/scripts

# 创建 runtime 目录
RUNTIME=/data/adb/kfm
mkdir -p "$RUNTIME/run" "$RUNTIME/logs" "$RUNTIME/scripts"
chmod 700 "$RUNTIME"

# 复制默认配置（仅首次安装）
if [ ! -f "$RUNTIME/config.json" ]; then
    cp $MODPATH/assets/default-config.json "$RUNTIME/config.json"
fi

# 复制示例脚本
cp -n $MODPATH/assets/example-scripts/*.js "$RUNTIME/scripts/" 2>/dev/null

ui_print "+ rustfrida binary installed to /system/bin"
ui_print "+ kfm dispatcher installed to /system/bin"
ui_print "+ Runtime dir: $RUNTIME"
ui_print ""
ui_print "Next steps:"
ui_print "  1. Reboot device"
ui_print "  2. Use 'kfm help' in terminal"
ui_print "  3. Or install KFM Controller app"
ui_print ""
