#!/bin/bash
# send2kindle.sh — 智能发送文件到 Kindle
# 依赖: cliclick, pillow, fswatch
# 用法:
#   send2kindle.sh /path/file1.pdf /path/file2.docx
#   send2kindle.sh                                   # 当前目录所有支持的文件
#   send2kindle.sh --watch /path/to/dir              # 监控目录自动发送

set -euo pipefail

APP="Send to Kindle"
WIN_IMG="/tmp/send2kindle_win.png"
TMP_DIR="$HOME/.send2kindle_tmp"

# Kindle 原生支持的后缀
NATIVE_EXTS="pdf|epub|rtf|doc|docx|html|htm|jpg|jpeg|gif|png|bmp|txt|mobi|azw3"

# ---- 清理 ----
cleanup() { rm -rf "$TMP_DIR" "$WIN_IMG" 2>/dev/null || true; }
trap cleanup EXIT
# Clean old fail screenshots
find /tmp -name "send2kindle_fail_*.png" -mmin +5 -delete 2>/dev/null || true
mkdir -p "$TMP_DIR"

# ---- 颜色检测点击 Send 按钮 ----
click_send() {
    local wx wy sw sh
    read -r wx wy sw sh <<< "$(
        osascript -e "
            tell application \"System Events\"
                tell process \"$APP\"
                    set p to position of window 1
                    set s to size of window 1
                end tell
            end tell
            set px to item 1 of p
            set py to item 2 of p
            set swi to item 1 of s
            set shi to item 2 of s
            return (px as string) & \" \" & (py as string) & \" \" & (swi as string) & \" \" & (shi as string)
        " 2>/dev/null
    )"
    [ -z "$sh" ] && { echo "NO_WINDOW"; return 1; }

    screencapture -R "$wx,$wy,$sw,$sh" -t png "$WIN_IMG" 2>/dev/null

    python3 - "$WIN_IMG" "$wx" "$wy" "$sw" "$sh" << 'PYEOF' 2>/dev/null
import sys
from PIL import Image
from collections import defaultdict

img_path, wx, wy, sw, sh = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
img = Image.open(img_path)
w_img, h_img = img.size
pixels = img.load()
scale = w_img / sw

candidates = []
for y in range(h_img):
    for x in range(w_img):
        r, g, b = pixels[x, y][:3]
        if b > 200 and r < 150 and g < 200 and r + g + b > 300:
            candidates.append((x, y))

if not candidates:
    print("NO_BUTTON", flush=True)
    sys.exit(1)

y_groups = defaultdict(list)
for x, y in candidates:
    y_groups[y // 10].append((x, y))
best = max(y_groups.values(), key=len)
xs = [p[0] for p in best]
ys = [p[1] for p in best]
print(f"CLICK:{int(wx + sum(xs)/len(xs)/scale)},{int(wy + sum(ys)/len(ys)/scale)}", flush=True)
PYEOF
}

# ---- 转换文件为 PDF ----
convert_to_pdf() {
    local input="$1"
    local abs_input
    abs_input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
    local ext="${input##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    local basename
    basename="$(basename "$input" | sed 's/\.[^.]*$//')"
    local output="$TMP_DIR/${basename}.pdf"

    [ -f "$output" ] && { echo "$output"; return 0; }

    case "$ext" in
        pages)
            printf "    🖨️  Pages → PDF..." >&2
            osascript -e "
                tell application \"Pages\"
                    open POSIX file \"$abs_input\"
                    delay 2
                    tell front document
                        export to POSIX file \"$output\" as PDF
                        close
                    end tell
                end tell
            " 2>/dev/null
            ;;
        key)
            printf "    🖨️  Keynote → PDF..." >&2
            osascript -e "
                tell application \"Keynote\"
                    open POSIX file \"$abs_input\"
                    delay 2
                    tell front document
                        export to POSIX file \"$output\" as PDF
                        close
                    end tell
                end tell
            " 2>/dev/null
            ;;
        numbers)
            printf "    🖨️  Numbers → PDF..." >&2
            osascript -e "
                tell application \"Numbers\"
                    open POSIX file \"$abs_input\"
                    delay 2
                    tell front document
                        export to POSIX file \"$output\" as PDF
                        close
                    end tell
                end tell
            " 2>/dev/null
            ;;
        md|markdown|txt|rtf|text)
            printf "    🖨️  文本 → PDF..." >&2
            textutil -convert html -output "$TMP_DIR/${basename}.html" "$abs_input" 2>/dev/null && \
            python3 -c "
import sys
with open('$TMP_DIR/${basename}.html', 'r') as f:
    html = f.read()
# Use basic HTML to PDF via Pillow + simple rendering
" 2>/dev/null || \
            cupsfilter "$abs_input" > "$output" 2>/dev/null
            ;;
        *)
            printf "    🖨️  cupsfilter → PDF..." >&2
            cupsfilter "$abs_input" > "$output" 2>/dev/null
            ;;
    esac

    if [ -f "$output" ] && [ -s "$output" ]; then
        echo " ✅" >&2
        echo "$output"
        return 0
    else
        echo " ❌" >&2
        return 1
    fi
}

# ---- 判断是否需转换 ----
needs_conversion() {
    local ext="${1##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    ! [[ "$ext" =~ ^($NATIVE_EXTS)$ ]]
}

# ---- 发送单个文件 ----
send_one() {
    local file="$1"
    local send_file="$file"

    [[ "$(basename "$file")" == .* ]] && return 0

    printf "📤 %-50s" "$(basename "$file")"

    if needs_conversion "$file"; then
        echo ""
        local converted
        if converted=$(convert_to_pdf "$file"); then
            send_file="$converted"
        else
            echo "    ❌ 无法转换，跳过"
            return 1
        fi
    fi

    osascript -e "quit app \"$APP\"" 2>/dev/null
    sleep 2

    open -a "$APP" "$send_file"; sleep 6

    local result
    local retry=0
    while [ $retry -lt 5 ]; do
        result=$(click_send || echo "FAIL")
        if [[ "$result" == CLICK:* ]]; then break; fi
        ((retry++))
        sleep 1
    done
    if [[ "$result" == CLICK:* ]]; then
        IFS=',' read -r sx sy <<< "${result#CLICK:}"
        cliclick "c:$sx,$sy" 2>/dev/null
        sleep 3
        echo "    ✅ 已发送"
    else
        echo "    ❌ 发送失败 ($result)"
        screencapture -t png "/tmp/send2kindle_fail_$(date +%s).png" 2>/dev/null
        return 1
    fi
}

# ---- 批量发送 ----
batch_send() {
    local files=("$@")
    [ ${#files[@]} -eq 0 ] && { echo "❌ 没有可发送的文件"; exit 1; }
    echo "📚 ${#files[@]} 个文件"
    local ok=0 fail=0
    for f in "${files[@]}"; do
        if send_one "$f"; then ((ok++)); else ((fail++)); fi
    done
    echo "🎉 $ok 成功, $fail 失败"
}

# ---- 监控目录 ----
watch_dir() {
    local dir="$1"
    echo "👀 监控目录: $dir (按 Ctrl+C 停止)"
    echo "   Kindle原生: pdf, epub, doc, docx, html, jpg, png, txt..."
    echo "   自动转换:  pages, key, numbers, md → PDF"
    echo ""
    fswatch -0 "$dir" --event Created --event Renamed --event MovedTo -e '^/\.' -i '\.' 2>/dev/null | \
    while IFS= read -r -d '' file; do
        [ -f "$file" ] || continue
        [[ "$(basename "$file")" == .* ]] && continue
        sleep 1
        # 去重：同一文件 10 秒内不重复发送
        local now
        now=$(date +%s)
        local last
        last=$(cat "/tmp/sk_last_${file//\//_}" 2>/dev/null || echo 0)
        if (( now - last < 10 )); then continue; fi
        echo "$now" > "/tmp/sk_last_${file//\//_}"
        send_one "$file" || true
    done
}

# ---- main ----
case "${1:-}" in
    --watch|-w) shift; watch_dir "${1:-.}" ;;
    *)
        if [ $# -gt 0 ]; then batch_send "$@"
        else
            shopt -s nullglob
            all_files=(*)
            batch_send "${all_files[@]}"
        fi
        ;;
esac
