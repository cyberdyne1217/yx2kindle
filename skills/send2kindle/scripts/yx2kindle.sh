#!/bin/bash
set -euo pipefail

TAG="ToKindle"
TMP_DIR="$HOME/.yx2kindle_tmp"
SENT_FILE="/tmp/yx2kindle_sent.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cleanup() { rm -rf "$TMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT

# Clean up any leftover TMP_DIR from previous runs
rm -rf "$TMP_DIR" 2>/dev/null
mkdir -p "$TMP_DIR"
touch "$SENT_FILE"

get_pending() {
    osascript -e "
tell application \"印象笔记\"
    set allNotes to find notes \"tag:$TAG\"
    set output to \"\"
    repeat with n in allNotes
        set output to output & (title of n) & \"\\n\"
    end repeat
    if output is \"\" then return \"EMPTY\"
    return output
end tell
" 2>/dev/null
}


export_html() {
    local t="${1//\"/\\\"}"
    osascript -e "
tell application \"印象笔记\"
    set allNotes to find notes \"tag:$TAG\"
    repeat with n in allNotes
        if (title of n) starts with \"$t\" then
            return HTML content of n
        end if
    end repeat
    return \"\"
end tell
" 2>/dev/null
}

process_one() {
    local title="$1"
    local safe="$(echo "$title" | tr '/: *?"<>|' '_' | cut -c1-60)"
    local html_file="$TMP_DIR/${safe}.html"
    local pdf_file="$TMP_DIR/${safe}.pdf"
    echo "  [yx2k] $title"
    local html
    html=$(export_html "$title")
    [ -z "$html" ] && { echo "    FAIL: cannot read"; return 1; }
    echo "$html" > "$html_file"
    echo "    HTML $(wc -c < "$html_file" | tr -d ' ') bytes"
    echo "    -> PDF..."
    if python3 "$SCRIPT_DIR/html2pdf.py" "$html_file" "$pdf_file" 2>/dev/null && [ -s "$pdf_file" ]; then
        echo "    PDF $(wc -c < "$pdf_file" | tr -d ' ') bytes"
    else
        echo "    PDF failed, using HTML"
        pdf_file="$html_file"
    fi
    if bash "$SCRIPT_DIR/send2kindle.sh" "$pdf_file" 2>&1; then
        echo "$title" >> "$SENT_FILE"
        return 0
    else
        echo "    FAIL: send error"
        return 1
    fi
}

run_once() {
    echo "[yx2k] Checking tag '$TAG'..."
    local notes
    notes=$(get_pending)
    case "$notes" in
        EMPTY|"") echo "  No pending notes."; return 0 ;;
    esac
    local count=0
    local ok=0 fail=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        line="${line%$'\r'}"
        local title="$line"
        # 跳过已发送的
        if grep -qF "$title" "$SENT_FILE" 2>/dev/null; then
            echo "  [skip] $title (already sent)"
            continue
        fi
        ((count++))
        if process_one "$title"; then ((ok++)); else ((fail++)); fi
    done <<< "$notes"
    if [ $count -eq 0 ]; then
        echo "  All notes already sent."
    else
        echo "[yx2k] Done: $ok ok, $fail fail"
    fi
}

case "${1:-}" in
    --watch|-w)
        echo "[yx2k] Watching tag '$TAG' (every 60s, Ctrl+C to stop)"
        while true; do run_once; echo; sleep 60; done ;;
    *) run_once ;;
esac
