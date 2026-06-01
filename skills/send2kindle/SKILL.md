---
name: send2kindle
description: Send files and 印象笔记 articles to Kindle via the macOS Send to Kindle app. Supports watching directories for auto-send, forwarding articles from 印象笔记 notebooks, and auto-converting Pages/Keynote/Numbers to PDF. Use when the user asks to send files to Kindle, forward 印象笔记 articles to Kindle, or set up automated Kindle delivery workflows.
---

# Send to Kindle

Send files to a Kindle device through the macOS "Send to Kindle" app. Supports directory monitoring and automatic format conversion.

## Quick usage

The primary script is `scripts/send2kindle.sh`. It requires:
- macOS "Send to Kindle" app (from App Store)
- `cliclick` (`brew install cliclick`)
- `fswatch` (`brew install fswatch`)
- `pillow` (`pip3 install Pillow`)

### Watch a directory (auto-send on file drop)

```bash
bash scripts/send2kindle.sh --watch /path/to/watch/dir
```

Files dragged or copied into the watched directory are automatically sent. Deduplication ensures each file is sent once within a 10-second window.

### Send specific files

```bash
bash scripts/send2kindle.sh /path/file1.pdf /path/file2.docx
```

### Send all files in current directory

```bash
bash scripts/send2kindle.sh
```

## Supported formats

**Sent directly (Kindle native):** pdf, epub, rtf, doc, docx, html, htm, jpg, jpeg, gif, png, bmp, txt, mobi, azw3

**Auto-converted to PDF:** pages, key, numbers, md, markdown, rtf, txt

Pages/Keynote/Numbers conversion uses the respective macOS app via AppleScript. The app will briefly open and close during conversion — this is normal.

For any other format, `cupsfilter` is attempted as a fallback.

## How it works

1. `fswatch` monitors the directory for file creation/move events
2. Files matching Kindle-native formats are sent directly via `open -a "Send to Kindle"`
3. Non-native formats (e.g., `.pages`) are auto-converted to PDF first
4. The "Send" button in the app is clicked via color-detection (Pillow) + `cliclick`
5. Deduplication prevents the same file from being sent multiple times within 10 seconds
6. Temp files (`$HOME/.send2kindle_tmp/`, `/tmp/send2kindle_win.png`) are cleaned up via trap on exit
7. Old fail screenshots (`/tmp/send2kindle_fail_*.png` older than 5 min) are removed at startup

## Troubleshooting

- If the Send button isn't detected, the script saves a screenshot to `/tmp/send2kindle_fail_*.png` for debugging (auto-cleaned after 5 min)
- Pages/Keynote/Numbers apps must be installed for their respective conversions to work
- The "Send to Kindle" app window must be visible and not minimized


## 印象笔记文章转发到 Kindle

Use `scripts/yx2kindle.sh` to forward articles from an 印象笔记 notebook to Kindle:

1. Create a notebook called `待发送Kindle` in 印象笔记
2. Save articles (e.g. from WeChat public accounts) to this notebook
3. Run the forwarding script:

```bash
# One-time: send all pending articles
bash scripts/yx2kindle.sh

# Continuous: check every 60 seconds
bash scripts/yx2kindle.sh --watch
```

The script reads each article's HTML content from 印象笔记, exports it, and sends it to Kindle via `send2kindle.sh`. After successful delivery, the article is tagged `已发送Kindle` to avoid duplicates.

Temp files (`$HOME/.yx2kindle_tmp/`) are automatically cleaned up on exit via `trap cleanup EXIT`, even on Ctrl+C or errors. Leftover dirs from previous runs are also removed at startup.

**Workflow summary:** WeChat article → save to 印象笔记 `待发送Kindle` → `yx2kindle.sh` → Kindle
