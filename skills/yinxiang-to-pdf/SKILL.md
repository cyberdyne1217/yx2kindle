---
name: yinxiang-to-pdf
description: Export 印象笔记 (Yinxiang Biji) notes to clean, print-ready PDF files with embedded images. Use when the user asks to convert an 印象笔记 note to PDF, export a note as PDF, or save a Yinxiang note for Kindle/offline reading.
---

# Yinxiang to PDF

Export 印象笔记 notes to PDF using the bundled `scripts/export_note_to_pdf.py` script.

## Quick Start

```bash
python3 scripts/export_note_to_pdf.py "笔记标题关键词"
```

This searches 印象笔记 by AppleScript, exports all attachments, cleans up the HTML,
embeds images as base64, and prints to PDF via Chrome headless.

## Options

- `--output <path>` — Custom output path (default: `~/Downloads/<title>.pdf`)

## How It Works

1. **Find the note** — AppleScript searches 印象笔记 by title keyword (fuzzy match)
2. **Export attachments** — All images are written to a temp directory via AppleScript
3. **Clean HTML** — Strips `display:none`, `<style>`, `<script>`, `<link>`, `<svg>` tags
4. **Embed images** — Replaces `<img src>` with base64 data URIs (preserves original order)
5. **Chrome print** — Uses Chrome headless `--print-to-pdf` with an anchor div workaround for the blank-first-page bug
6. **Remove blanks** — Strips PDF pages with < 10 text operations and no images

## Important Details

- Requires Google Chrome installed at `/Applications/Google Chrome.app`
- The anchor div (`<div class="anchor">.</div>`) with 1px height works around a Chrome headless bug where the first page renders blank
- Attachment filenames from AppleScript may show as "missing value" — the script detects actual MIME types via `file --mime-type`
- PDF is vector text, suitable for Kindle and other e-readers
- **PDF page counting**: Chrome generates nested `/Pages` trees (not just a flat `/Kids` array). The `count_pdf_pages()` function recursively traverses all `/Pages` objects via a stack to correctly count every leaf `/Page`. A flat-read approach would undercount (e.g., 8 instead of 42).
