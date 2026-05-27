#!/bin/bash
set -euo pipefail

WATCH_TAG="ToKindle"
WORK_DIR="/tmp/yx2kindle"
CLICK="/opt/homebrew/bin/cliclick"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# === 从截图中找蓝色按钮位置 ===
find_button() {
    local screenshot="$1"
    local region="${2:-full}"  # full / pdf_popup / save_panel
    local mode="${3:-center}"  # center / top
    python3 -c "
from PIL import Image
img = Image.open('$screenshot')
small = img.resize((1512, 982))

if '$region' == 'pdf_popup':
    # PDF 弹出按钮在左下角
    x_range = range(30, 300)
    y_range = range(870, 950)
elif '$region' == 'save_panel':
    # 存储按钮在右下角
    x_range = range(1000, 1480)
    y_range = range(800, 950)
else:
    x_range = range(0, small.width)
    y_range = range(0, small.height)

best = None
best_score = 0
found_all = []

for y in y_range:
    for x in x_range:
        px = small.getpixel((x, y))
        r, g, b = px[0], px[1], px[2]
        score = b - r
        if '$region' == 'pdf_popup':
            # 找 PDF 蓝色文字按钮
            if b > 160 and r < 100 and g > 60:
                found_all.append((x, y, score))
        elif '$region' == 'save_panel':
            # 找深蓝色存储按钮（macOS 按钮 #3367d6 附近）
            if score > 100 and b > 150 and r < 100:
                if score > best_score:
                    best_score = score
                    best = (x, y)
        else:
            if score > 100 and b > 150 and r < 100:
                if score > best_score:
                    best_score = score
                    best = (x, y)

if best:
    print(f'{best[0]},{best[1]}')
elif found_all:
    # PDF 按钮：取最左上角的蓝色像素
    if '$mode' == 'top':
        found_all.sort(key=lambda p: p[1])  # 按 y 排序，取最上面
    else:
        xs = [p[0] for p in found_all]
        ys = [p[1] for p in found_all]
        mid = len(found_all) // 2
        found_all.sort(key=lambda p: (p[1], p[0]))
        cx = sum(xs) // len(xs)
        cy = sum(ys) // len(ys)
        # 对于 PDF 弹出按钮，我们想要按钮文字中心偏右
        print(f'{cx+20},{cy-5}')
        exit()
    if found_all:
        best = found_all[0]
        print(f'{best[0]+20},{best[1]-5}')
else:
    print('NOT_FOUND')
"
}

# === 从印象笔记打印一篇笔记到 PDF ===
print_note_to_pdf() {
    local note_title="$1"
    local pdf_path="$2"
    
    log "Printing: $note_title"
    
    # 1. 打开笔记
    osascript -e "
    tell application \"印象笔记\"
        set noteList to find notes \"intitle:\\\"${note_title}\\\" tag:${WATCH_TAG}\"
        if (count of noteList) = 0 then error \"Note not found\"
        open note window with (item 1 of noteList)
    end tell
    " 2>/dev/null
    sleep 2
    
    # 2. Cmd+P
    osascript -e '
    tell application "System Events"
        tell process "Evernote"
            set frontmost to true
            delay 0.5
            keystroke "p" using command down
        end tell
    end tell
    '
    sleep 6
    
    # 3. 截图，定位 PDF 弹出按钮
    screencapture /tmp/yx_step1.png
    local pdf_btn
    pdf_btn=$(find_button /tmp/yx_step1.png pdf_popup)
    
    if [ "$pdf_btn" = "NOT_FOUND" ]; then
        log "ERROR: PDF button not found"
        return 1
    fi
    
    log "PDF button at: $pdf_btn"
    $CLICK c:$pdf_btn
    sleep 1.5
    
    # 4. 截图，定位"保存为PDF…"菜单项（菜单最顶部）
    screencapture /tmp/yx_step2.png
    local pdf_menu_item
    pdf_menu_item=$(find_button /tmp/yx_step2.png save_panel top)
    
    if [ "$pdf_menu_item" = "NOT_FOUND" ]; then
        # 菜单可能没弹出，用 PDF 按钮上方偏移
        local pdf_x pdf_y
        IFS=',' read -r pdf_x pdf_y <<< "$pdf_btn"
        pdf_menu_item="$pdf_x,$((pdf_y - 70))"
        log "Menu not found in screenshot, using offset: $pdf_menu_item"
    else
        log "PDF menu item at: $pdf_menu_item"
    fi
    
    $CLICK c:$pdf_menu_item
    sleep 4
    
    # 5. 截图，定位存储按钮
    screencapture /tmp/yx_step3.png
    local store_btn
    store_btn=$(find_button /tmp/yx_step3.png save_panel)
    
    if [ "$store_btn" = "NOT_FOUND" ]; then
        log "ERROR: Store button not found"
        return 1
    fi
    
    log "Store button at: $store_btn"
    $CLICK c:$store_btn
    sleep 5
    
    # 6. 检查 PDF
    if [ -f "$pdf_path" ]; then
        log "PDF: $pdf_path ($(ls -lh "$pdf_path" | awk '{print $5}'))"
        return 0
    fi
    
    # 查找其他可能的 PDF 文件名
    local found
    found=$(find ~/Desktop ~/Downloads -name "*.pdf" -mmin -1 2>/dev/null | head -3)
    if [ -n "$found" ]; then
        log "Found new PDF(s): $found"
        # 取最新的
        local latest
        latest=$(ls -t $found | head -1)
        cp "$latest" "$pdf_path"
        log "Copied to: $pdf_path"
        return 0
    fi
    
    log "ERROR: No PDF generated"
    return 1
}

# === 发送到 Kindle ===
send_to_kindle() {
    local pdf="$1"
    if [ -d "/Applications/Send to Kindle.app" ]; then
        open -a "Send to Kindle" "$pdf"
        sleep 3
        log "Sent to Kindle"
    fi
}

# === 主流程 ===
process_once() {
    mkdir -p "$WORK_DIR"
    log "Scanning for tag: $WATCH_TAG"
    
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
        log "No notes found"
        return
    fi
    
    echo "$titles" | while IFS= read -r title; do
        [ -z "$title" ] && continue
        log "=== $title ==="
        
        local safe
        safe=$(echo "$title" | tr '/' '_' | tr ':' '_')
        local pdf="$HOME/Desktop/${safe}.pdf"
        
        if print_note_to_pdf "$title" "$pdf"; then
            send_to_kindle "$pdf"
        fi
    done
    
    log "All done"
}

process_watch() {
    log "Watching tag '$WATCH_TAG' every 60s"
    while true; do
        local n
        n=$(osascript -e "
        tell application \"印象笔记\"
            return count of (find notes \"tag:${WATCH_TAG}\")
        end tell
        " 2>/dev/null || echo 0)
        
        [ "${n:-0}" -gt 0 ] 2>/dev/null && { log "Found $n notes"; process_once; }
        sleep 60
    done
}

case "${1:-}" in
    --watch|-w) process_watch ;;
    --once|-o)  process_once ;;
    *)          echo "Usage: $0 [--watch | --once]" ;;
esac
