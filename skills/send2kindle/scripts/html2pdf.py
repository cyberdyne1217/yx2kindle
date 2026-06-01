#!/usr/bin/env python3
"""印象笔记 HTML → PDF：Playwright 渲染纯文字排版"""
import sys, os, re, tempfile, shutil

def clean_html(raw: str) -> str:
    html = re.sub(r'<img[^>]*class="en-media"[^>]*/?>', '<p style="color:#999;text-align:center;padding:20px">[ 图片 ]</p>', raw)
    html = re.sub(r'<img[^>]*en-media[^>]*/?>', '<p style="color:#999;text-align:center;padding:20px">[ 图片 ]</p>', html)
    html = re.sub(r'var\(--weui-[^)]+\)', 'initial', html)
    html = re.sub(r'<div style="display:\s*none[^"]*">.*?</div>', '', html, flags=re.DOTALL)
    return html

def wrap_html(body: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; }}
  body {{ font-family: "PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif; font-size:16px; line-height:1.8; max-width:750px; margin:30px auto; padding:0 20px; color:#333; }}
  h1 {{ font-size:22px; font-weight:700; margin:20px 0 12px; }}
  h2 {{ font-size:18px; font-weight:600; margin:16px 0 8px; }}
  pre,code {{ background:#f5f5f5; border-radius:4px; font-size:13px; }}
  pre {{ padding:12px; white-space:pre-wrap; }}
  blockquote {{ border-left:3px solid #4A90D9; padding:8px 16px; margin:12px 0; background:#f0f7ff; }}
  li {{ margin:4px 0; }}
</style></head>
<body>{body}</body></html>"""

def html_to_pdf(html_path: str, pdf_path: str) -> bool:
    with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
        raw = f.read()
    
    html = wrap_html(clean_html(raw))
    tmp = tempfile.NamedTemporaryFile(suffix='.html', mode='w', encoding='utf-8', delete=False)
    tmp.write(html)
    tmp.close()
    browser = None
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 800, "height": 600})
            page.goto("file://" + tmp.name, timeout=15000)
            page.wait_for_timeout(1000)
            page.pdf(path=pdf_path, print_background=True)
        ok = os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 100
    except Exception:
        ok = False
    finally:
        # Always close browser if it was started
        if browser is not None:
            try:
                browser.close()
            except Exception:
                pass
        # Clean up temp HTML
        try:
            os.unlink(tmp.name)
        except OSError:
            pass
    return ok

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: html2pdf.py input.html output.pdf"); sys.exit(1)
    ok = html_to_pdf(sys.argv[1], sys.argv[2])
    sys.exit(0 if ok else 1)
