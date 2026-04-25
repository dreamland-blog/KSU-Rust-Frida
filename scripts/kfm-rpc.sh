#!/system/bin/sh
# kfm-rpc.sh - 通过 HTTP RPC 与 rustfrida 通信
# rustfrida --server 模式下暴露 HTTP 端口，支持远程调用 JS 函数
#
# 用法:
#   kfm rpc call <func> [args...]  - 调用导出的 JS 函数
#   kfm rpc eval <code>            - 执行 JS 代码片段
#   kfm rpc sessions               - 列出活跃 session

RUNTIME_DIR="/data/adb/kfm"
RPC_PORT_FILE="$RUNTIME_DIR/run/rpc.port"

. /data/adb/modules/ksu-frida-manager/scripts/lib/common.sh

# 读取 RPC 端口
if [ ! -f "$RPC_PORT_FILE" ]; then
    json_error "rustfrida server not running (no RPC port file)"
    exit 1
fi
RPC_PORT=$(cat "$RPC_PORT_FILE")

SUBCMD="${1:-help}"
shift 2>/dev/null || true

case "$SUBCMD" in
    call)
        FUNC="$1"
        shift 2>/dev/null || true
        if [ -z "$FUNC" ]; then
            json_error "usage: kfm rpc call <function_name> [args...]"
            exit 1
        fi
        # 构造 JSON 参数
        ARGS_JSON="["
        FIRST=1
        for arg in "$@"; do
            [ "$FIRST" = "1" ] && FIRST=0 || ARGS_JSON="$ARGS_JSON,"
            ARGS_JSON="$ARGS_JSON\"$arg\""
        done
        ARGS_JSON="$ARGS_JSON]"

        wget -qO- --post-data="{\"function\":\"$FUNC\",\"args\":$ARGS_JSON}" \
            "http://127.0.0.1:$RPC_PORT/rpc/call" 2>/dev/null || \
            json_error "RPC call failed"
        ;;
    eval)
        CODE="$*"
        if [ -z "$CODE" ]; then
            json_error "usage: kfm rpc eval <javascript_code>"
            exit 1
        fi
        wget -qO- --post-data="{\"code\":\"$CODE\"}" \
            "http://127.0.0.1:$RPC_PORT/rpc/eval" 2>/dev/null || \
            json_error "RPC eval failed"
        ;;
    sessions)
        wget -qO- "http://127.0.0.1:$RPC_PORT/sessions" 2>/dev/null || \
            json_error "failed to list sessions"
        ;;
    *)
        cat <<EOF
kfm rpc - HTTP RPC interface to rustfrida

USAGE:
    kfm rpc call <func> [args...]   Call exported JS function
    kfm rpc eval <code>             Execute JS code
    kfm rpc sessions                List active sessions

EXAMPLES:
    kfm rpc call dumpClasses
    kfm rpc eval "Java.available"
    kfm rpc sessions
EOF
        ;;
esac
