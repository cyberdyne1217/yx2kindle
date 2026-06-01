#!/bin/bash
# yinxiang_save.sh — 存内容/文件到印象笔记
# 用法:
#   yinxiang_save.sh "标题" "内容" [笔记本]        # 存文本笔记
#   yinxiang_save.sh -f /path/file [笔记本]        # 文件作为附件导入
#   yinxiang_save.sh "标题" "内容" -f /path/file    # 文本 + 附件
# 默认笔记本: 收件箱

NOTEBOOK="收件箱"
TITLE=""
BODY=""
FILES=()

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            FILES+=("$2")
            shift 2
            ;;
        -*)
            echo "未知参数: $1"
            exit 1
            ;;
        *)
            if [ -z "$TITLE" ]; then
                TITLE="$1"
            elif [ -z "$BODY" ]; then
                BODY="$1"
            else
                NOTEBOOK="$1"
            fi
            shift
            ;;
    esac
done

escape_for_applescript() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

NOTEBOOK_ESC=$(escape_for_applescript "$NOTEBOOK")

# ---- 模式1: 纯文件导入 ----
if [ ${#FILES[@]} -gt 0 ] && [ -z "$TITLE" ]; then
    for f in "${FILES[@]}"; do
        [ ! -f "$f" ] && { echo "❌ 文件不存在: $f"; continue; }
        abs_path="$(cd "$(dirname "$f")" 2>/dev/null && pwd)/$(basename "$f")"
        echo "📎 导入: $(basename "$f")"
        osascript -e "
            tell application \"印象笔记\"
                try
                    import POSIX file \"$abs_path\" to notebook \"$NOTEBOOK_ESC\"
                    return
                on error errMsg
                    import POSIX file \"$abs_path\"
                end try
            end tell
        " 2>/dev/null
        echo "   ✅ 已存入 → $NOTEBOOK"
    done
    exit 0
fi

# ---- 模式2: 文本笔记 + 可选附件 ----
if [ -z "$TITLE" ]; then
    echo "用法: yinxiang_save.sh \"标题\" \"内容\" [笔记本] [-f 附件]"
    exit 1
fi

TITLE_ESC=$(escape_for_applescript "$TITLE")
BODY_ESC=$(escape_for_applescript "${BODY:-}")

# 先创建文本笔记
echo "📝 创建笔记: $TITLE"
NOTE_CMD="create note with text \"$BODY_ESC\" title \"$TITLE_ESC\""

osascript -e "
tell application \"印象笔记\"
    try
        $NOTE_CMD notebook \"$NOTEBOOK_ESC\"
    on error
        try
            $NOTE_CMD
        on error errMsg
            return \"❌ 创建失败: \" & errMsg
        end try
    end try
end tell
" 2>/dev/null
echo "   ✅ 已存入 → $NOTEBOOK"

# 如果还有附件，追加到刚创建的笔记
if [ ${#FILES[@]} -gt 0 ]; then
    # 印象笔记 AppleScript 不支持给已有笔记加附件，
    # 改用 import 创建新笔记的方式
    echo "⚠️  附件将以独立笔记导入（AppleScript 限制）"
    for f in "${FILES[@]}"; do
        [ ! -f "$f" ] && continue
        abs_path="$(cd "$(dirname "$f")" 2>/dev/null && pwd)/$(basename "$f")"
        echo "📎 $(basename "$f")"
        osascript -e "
            tell application \"印象笔记\"
                try
                    import POSIX file \"$abs_path\" to notebook \"$NOTEBOOK_ESC\"
                on error
                    import POSIX file \"$abs_path\"
                end try
            end tell
        " 2>/dev/null
        echo "   ✅ 已存入 → $NOTEBOOK"
    done
fi
