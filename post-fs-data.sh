#!/system/bin/sh
# post-fs-data.sh - 开机前期执行
# 仅确保目录存在，不做任何 frida 相关操作
mkdir -p /data/adb/kfm/run /data/adb/kfm/logs
