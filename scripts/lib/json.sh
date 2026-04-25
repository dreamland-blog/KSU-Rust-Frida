#!/system/bin/sh
# json.sh - 简易 JSON 构造工具
# 在 toybox sh 环境下构造 JSON 输出（无 jq 依赖）

# 输出一个 JSON 对象
# 用法: json_obj "key1" "val1" "key2" "val2" ...
# 数字类型的值不加引号，其他加引号
json_obj() {
    printf '{'
    _FIRST=1
    while [ $# -ge 2 ]; do
        _KEY="$1"
        _VAL="$2"
        shift 2

        [ "$_FIRST" = "1" ] && _FIRST=0 || printf ','

        # 判断值类型
        case "$_VAL" in
            true|false|null|[0-9]|[0-9]*[0-9])
                printf '"%s":%s' "$_KEY" "$_VAL"
                ;;
            *)
                printf '"%s":"%s"' "$_KEY" "$_VAL"
                ;;
        esac
    done
    printf '}'
}

# 构造 JSON 数组
# 用法: json_array "val1" "val2" ...
json_array() {
    printf '['
    _FIRST=1
    for _ITEM in "$@"; do
        [ "$_FIRST" = "1" ] && _FIRST=0 || printf ','
        printf '"%s"' "$_ITEM"
    done
    printf ']'
}

# 转义 JSON 字符串中的特殊字符
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g'
}
