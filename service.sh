#!/system/bin/sh
# service.sh - 开机后期执行
# 铁律：绝不启动任何 frida/rustfrida 进程，只做清理和准备

RUNTIME_DIR="/data/adb/kfm"

# 等系统完全启动
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 5

# 清理上次运行残留
rm -f "$RUNTIME_DIR/run/rustfrida.pid"
rm -f "$RUNTIME_DIR/run/rpc.port"

# 杀掉意外残留的 rustfrida 进程
pkill -9 -f rustfrida 2>/dev/null

# 确保 runtime 目录存在且权限正确
mkdir -p "$RUNTIME_DIR/run" "$RUNTIME_DIR/logs" "$RUNTIME_DIR/scripts"
chmod 700 "$RUNTIME_DIR"

# 记日志
echo "[$(date)] KFM service.sh: boot cleanup done" >> "$RUNTIME_DIR/logs/kfm.log"
