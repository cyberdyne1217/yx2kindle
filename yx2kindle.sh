#!/bin/bash
# yx2kindle.sh - 微信文章 → 印象笔记 → PDF → Kindle
# 用法: ./yx2kindle.sh --once | --watch

set -euo pipefail

WATCH_TAG="ToKindle"
DONE_TAG="kindled"
SKILL_DIR="$HOME/.codex/skills"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# === 处理一篇笔记 ===
process_note() {
    local title="$1"
    log "=== $title ==="
    
    # 安全文件名：保留原标题，超长时截断加...
    local safe_name
    if [ ${#title} -gt 60 ]; then
        safe_name="${title:0:57}..."
    else
        safe_name="$title"
    fi
    safe_name=$(echo "$safe_name" | tr '/' '／' | tr ':' '：')
    local pdf="$HOME/Desktop/${safe_name}.pdf"
    local tmp_pdf="/tmp/yx2kindle_$$.pdf"
    
    # 1. yinxiang-to-pdf
    log "  → PDF..."
    if ! python3 "$SKILL_DIR/yinxiang-to-pdf/scripts/export_note_to_pdf.py" "$title" --output "$tmp_pdf" 2>&1; then
        log "  ✗ PDF 失败"
        return 1
    fi
    
    # 移到桌面（使用原标题作为文件名）
    mv "$tmp_pdf" "$pdf"
    log "  ✓ PDF: $pdf"
    
    # 2. send2kindle
    log "  → Kindle..."
    if ! bash "$SKILL_DIR/send2kindle/scripts/send2kindle.sh" "$pdf" 2>&1; then
        log "  ✗ Kindle 发送失败"
        return 1
    fi
    log "  ✓ 已发送到 Kindle"
    
    # 3. 更新标签
    log "  → 标签..."
    osascript -e "
    tell application \"印象笔记\"
        set tkList to find notes \"tag:${WATCH_TAG}\"
        repeat with n in tkList
            if title of n contains \"$title\" then
                assign tag \"${DONE_TAG}\" to n
                unassign tag \"${WATCH_TAG}\" from n
                exit repeat
            end if
        end repeat
    end tell
    " 2>/dev/null
    log "  ✓ 标签已更新"
}

# === 处理一次 ===
process_once() {
    local titles
    titles=$(osascript -e "
    tell application \"印象笔记\"
        set noteList to find notes \"tag:${WATCH_TAG}\"
        set output to \"\"
        repeat with n in noteList
            set output to output & (title of n) & \"\n\"
        end repeat
        return output
    end tell
    " 2>/dev/null)
    
    if [ -z "$titles" ]; then
        log "没有待处理笔记"
        return
    fi
    
    local count=0
    echo "$titles" | while IFS= read -r title; do
        [ -z "$title" ] && continue
        process_note "$title" && count=$((count + 1))
    done
}

# === Watch ===
process_watch() {
    log "监控标签 '$WATCH_TAG' (每 60 秒)"
    while true; do
        local n
        n=$(osascript -e "
        tell application \"印象笔记\"
            return count of (find notes \"tag:${WATCH_TAG}\")
        end tell
        " 2>/dev/null || echo 0)
        
        [ "${n:-0}" -gt 0 ] 2>/dev/null && process_once
        sleep 60
    done
}

case "${1:-}" in
    --watch|-w) process_watch ;;
    --once|-o)  process_once ;;
    *)          echo "Usage: $0 [--watch | --once]" ;;
esac
