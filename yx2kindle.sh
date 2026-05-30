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
    local safe_name pdf
    safe_name=$(echo "$title" | tr '/' '_' | tr ':' '_' | tr -d '
')
    pdf="/tmp/yx2kindle_tmp_$$.pdf"  # 先用临时文件避免中文路径问题
    
    log "=== $title ==="
    
    # 1. yinxiang-to-pdf
    log "Generating PDF..."
    local tmp_pdf="/tmp/yx2kindle_$$.pdf"
    if ! python3 "$SKILL_DIR/yinxiang-to-pdf/scripts/export_note_to_pdf.py" "$title" --output "$tmp_pdf" 2>&1; then
        log "ERROR: PDF generation failed"
        return 1
    fi
    
    # Move to desktop with safe name
    mv "$tmp_pdf" "$pdf"
    
    # 2. send2kindle
    log "Sending to Kindle..."
    if ! bash "$SKILL_DIR/send2kindle/scripts/send2kindle.sh" "$pdf" 2>&1; then
        log "ERROR: Send to Kindle failed"
        return 1
    fi
    
    # 3. 更新标签
    log "Updating tags..."
    osascript -e "
    tell application \"印象笔记\"
        set noteList to find notes \"intitle:\\\"${title}\\\" tag:${WATCH_TAG}\"
        if (count of noteList) > 0 then
            set theNote to item 1 of noteList
            assign tag \"${DONE_TAG}\" to theNote
        end if
    end tell
    " 2>/dev/null
    
    log "Done: $title"
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
        log "No notes with tag $WATCH_TAG"
        return
    fi
    
    local count=0
    echo "$titles" | while IFS= read -r title; do
        [ -z "$title" ] && continue
        process_note "$title" && count=$((count + 1))
    done
    
    log "Processed $count notes"
}

# === Watch ===
process_watch() {
    log "Watching for tag '$WATCH_TAG' every 60s"
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
