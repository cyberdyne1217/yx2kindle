#!/usr/bin/env python3
"""
Export an 印象笔记 (Yinxiang Biji) note to a clean PDF.

Usage:
    python3 export_note_to_pdf.py "笔记标题关键词" [--output output.pdf]

The script:
1. Searches 印象笔记 for a note matching the title keyword
2. Exports the HTML content and all image attachments
3. Builds a clean HTML with embedded base64 images
4. Uses Chrome headless to print to PDF (with cleanup)
5. Removes any blank pages
"""

import os
import sys
import re
import zlib
import base64
import shutil
import signal
import subprocess
import tempfile
import argparse


def find_note(keyword):
    """Search 印象笔记 for a note containing the keyword in its title.
    Returns (title, guid, html_content, attachment_count) or None."""
    script = f'''
    tell application "印象笔记"
        set allNotes to find notes
        repeat with n in allNotes
            set noteTitle to title of n
            if noteTitle contains "{keyword}" then
                return title of n & " ||| " & (GUID of n) & " ||| " & (HTML content of n) & " ||| " & (count of attachments of n)
            end if
        end repeat
        return "NOT_FOUND"
    end tell
    '''
    result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True, timeout=30)
    output = result.stdout.strip()
    if output == "NOT_FOUND":
        return None
    parts = output.split(' ||| ', 3)
    if len(parts) < 4:
        return None
    title = parts[0]
    guid = parts[1]
    html_content = parts[2]
    try:
        attachment_count = int(parts[3])
    except ValueError:
        attachment_count = 0
    return title, guid, html_content, attachment_count


def export_attachments(keyword, output_dir):
    """Export all attachments from the matching note to output_dir.
    Returns (files, hash_map) where hash_map maps 印象笔记 hash -> file path."""
    files = []
    hash_map = {}
    for i in range(1, 100):
        idx = i
        out_path = os.path.join(output_dir, f'img_{idx}.png')
        script = f"""
        tell application "印象笔记"
            set allNotes to find notes
            repeat with n in allNotes
                if title of n contains "{keyword}" then
                    try
                        set a to attachment {idx} of n
                        write a to ("{out_path}" as POSIX file)
                        set h to hash of a
                        return "EXPORTED:" & h
                    on error
                        return "NO_MORE"
                    end try
                end if
            end repeat
            return "NOT_FOUND"
        end tell
        """
        result = subprocess.run(['osascript', '-e', script],
                                capture_output=True, text=True, timeout=15)
        stdout = result.stdout.strip()
        if stdout.startswith('EXPORTED:') and os.path.exists(out_path):
            h = stdout.split(':', 1)[1]
            files.append(out_path)
            hash_map[h] = out_path
        else:
            break
    return files, hash_map


def img_to_data_uri(filepath):
    """Convert an image file to a base64 data URI."""
    mime = subprocess.run(['file', '--mime-type', '-b', filepath],
                          capture_output=True, text=True).stdout.strip()
    with open(filepath, 'rb') as f:
        b64 = base64.b64encode(f.read()).decode()
    return f'data:{mime};base64,{b64}'


def clean_html(raw_html):
    """Clean up 印象笔记 HTML: remove display:none, style/script/link tags, SVGs."""
    html = raw_html
    html = re.sub(r'\bdisplay\s*:\s*none\s*[;]?', '', html, flags=re.IGNORECASE)
    html = re.sub(r'<style[^>]*>.*?</style>', '', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
    html = re.sub(r'<link[^>]*>', '', html, flags=re.IGNORECASE)
    html = re.sub(r'<svg[^>]*>.*?</svg>', '', html, flags=re.DOTALL)
    return html


def embed_images(html, image_files, hash_map):
    """Replace <img> src attributes with base64 data URIs.
    Matches by 印象笔记 hash instead of index order."""
    img_tags = list(re.finditer(r'<img[^>]*src="\?hash=([^"]+)"[^>]*>', html, re.IGNORECASE))
    for m in img_tags:
        hash_val = m.group(1)
        if hash_val in hash_map:
            uri = img_to_data_uri(hash_map[hash_val])
            html = html.replace(m.group(0), m.group(0).replace('?hash=' + hash_val, uri), 1)
    # Fallback: any remaining ?hash= images (shouldn't happen)
    remaining = list(re.finditer(r'<img[^>]*src="\?hash=([^"]+)"[^>]*>', html, re.IGNORECASE))
    for i, m in enumerate(remaining):
        if i < len(image_files):
            uri = img_to_data_uri(image_files[i])
            html = html.replace(m.group(0), m.group(0).replace('?hash=' + m.group(1), uri), 1)
    return html


def build_clean_html(original_html, note_title=None):
    """Wrap cleaned HTML in a proper document with print-friendly CSS and anchor fix.
    If note_title is provided and the body doesn't already have an <h1>, prepend one."""
    # Check if body already has its own <h1>
    body_match = re.search(r'<body[^>]*>(.*?)</body>', original_html, re.DOTALL | re.IGNORECASE)
    has_h1 = False
    if body_match and note_title:
        has_h1 = bool(re.search(r'<h1[ >]', body_match.group(1), re.IGNORECASE))
    
    title_block = ''
    if note_title and not has_h1:
        title_block = f'<h1>{note_title}</h1>\n'

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8">
<style>
  @media print {{
    @page {{ margin: 15mm 12mm 15mm 12mm; size: A4; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    font-family: "PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
    font-size: 14px; line-height: 1.8; color: #333;
    max-width: 700px; margin: 0 auto; padding: 20px 16px;
  }}
  .anchor {{ height: 1px; }}
  img {{ max-width: 100%; height: auto; display: block; margin: 12px auto; }}
  h1 {{ font-size: 20px; font-weight: 700; margin: 16px 0 10px; }}
  h2 {{ font-size: 17px; font-weight: 600; margin: 14px 0 8px; }}
  h3 {{ font-size: 15px; font-weight: 600; margin: 12px 0 6px; }}
  pre, code {{ background: #f5f5f5; border-radius: 4px; font-size: 12px; }}
  pre {{ padding: 10px; white-space: pre-wrap; overflow-x: auto; }}
  blockquote {{
    border-left: 3px solid #4A90D9; padding: 6px 14px; margin: 10px 0; background: #f0f7ff;
  }}
  table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
  td, th {{ border: 1px solid #ddd; padding: 6px 8px; }}
  li {{ margin: 3px 0; }}
  a {{ color: #4A90D9; }}
</style></head>
<body>
<div class="anchor">.</div>
{title_block}
{original_html}
</body></html>"""


def chrome_print_to_pdf(html_path, pdf_path):
    """Use Chrome headless to print HTML to PDF.
    Returns the Chrome process so it can be explicitly terminated."""
    chrome_path = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
    proc = subprocess.Popen(
        [chrome_path, '--headless', '--disable-gpu', '--no-sandbox',
         f'--print-to-pdf={pdf_path}', '--no-pdf-header-footer',
         f'file://{html_path}'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        proc.wait(timeout=45)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        return False
    return os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 0


def count_pdf_pages(data):
    """Recursively count all leaf /Page objects in the /Pages tree."""
    # Find the root /Pages object
    pages_match = re.search(rb'/Type\s*/Pages\s*(.*?)>>', data, re.DOTALL)
    if not pages_match:
        # Fallback: find any /Pages
        pages_match = re.search(rb'<<\s*(.*?)/Type\s*/Pages\s*(.*?)>>', data, re.DOTALL)
    
    def get_kids_refs(pages_dict):
        """Extract kid references from a /Pages dictionary."""
        kids = re.findall(rb'/Kids\s*\[([^\]]*)\]', pages_dict)
        if not kids:
            return []
        refs = re.findall(rb'(\d+)\s+(\d+)\s+R', kids[0])
        return refs
    
    def is_pages_obj(obj_data):
        return rb'/Type\s*/Pages' in obj_data or b'/Kids' in obj_data
    
    def get_page_content(obj_data):
        """Get text/image counts from a page object."""
        contents = re.search(rb'/Contents\s+(\d+\s+\d+\s+R)', obj_data)
        if not contents:
            return 0, 0
        cnum, cgen = contents.group(1).decode().split()[:2]
        cobj = re.search(f'{cnum}\\s+{cgen}\\s+obj.*?>>\\s*stream\\s(.*?)endstream'.encode(), data, re.DOTALL)
        if not cobj:
            return 0, 0
        try:
            dec = zlib.decompress(cobj.group(1).strip()).decode('latin-1', errors='replace')
        except Exception:
            dec = cobj.group(1).decode('latin-1', errors='replace')
        tj = dec.count('Tj') + dec.count('TJ')
        img = dec.count('Do')
        return tj, img
    
    # Find root /Pages
    root_pages_match = re.search(rb'<<\s*/Type\s*/Pages\s*(.*?)>>', data, re.DOTALL)
    if not root_pages_match:
        # Try broader search
        root_pages_match = re.search(rb'/Type\s*/Pages[^>]*>>', data, re.DOTALL)
    if not root_pages_match:
        return [], []
    
    all_page_refs = []
    blank_page_refs = []
    stack = [root_pages_match.group(0)]
    
    while stack:
        current = stack.pop()
        refs = get_kids_refs(current)
        for num, gen in refs:
            obj_match = re.search(f'{num}\\s+{gen}\\s+obj.*?endobj'.encode(), data, re.DOTALL)
            if not obj_match:
                continue
            obj_data = obj_match.group(0)
            if is_pages_obj(obj_data):
                stack.append(obj_data)
            else:
                # It's a leaf /Page
                all_page_refs.append((num, gen))
                tj, img = get_page_content(obj_data)
                if tj <= 10 and img == 0:
                    blank_page_refs.append((num, gen))
    
    return all_page_refs, blank_page_refs


def remove_blank_pages(pdf_path):
    """Remove pages from PDF that have no substantial content."""
    with open(pdf_path, 'rb') as f:
        data = f.read()

    all_refs, blank_refs = count_pdf_pages(data)
    print(f"  Total pages: {len(all_refs)}, blank: {len(blank_refs)}")
    
    if not blank_refs:
        return
    
    # Remove blank pages from the /Kids array
    km = re.search(rb'/Kids\s*\[([^\]]*)\]', data)
    if not km:
        return
    
    refs_in_kids = re.findall(rb'(\d+)\s+(\d+)\s+R', km.group(0))
    blank_set = set(blank_refs)
    new_refs = [r for r in refs_in_kids if r not in blank_set]
    
    old_kids = km.group(0)
    new_kids_str = b'/Kids [' + b' '.join(f'{n} {g} R'.encode() for n, g in new_refs) + b']'
    data = data.replace(old_kids, new_kids_str, 1)
    data = re.sub(rb'/Count\s+\d+', f'/Count {len(new_refs)}'.encode(), data, count=1)
    
    with open(pdf_path, 'wb') as f:
        f.write(data)


def main():
    parser = argparse.ArgumentParser(
        description='Export an 印象笔记 note to PDF')
    parser.add_argument('keyword', help='Keyword to search in note title')
    parser.add_argument('--output', '-o', default=None,
                        help='Output PDF path (default: ~/Downloads/<title>.pdf)')
    args = parser.parse_args()

    keyword = args.keyword
    img_dir = None

    try:
        # Step 1: Find the note
        print(f"Searching 印象笔记 for: '{keyword}'...")
        note_info = find_note(keyword)
        if not note_info:
            print(f"ERROR: No note found matching '{keyword}'")
            sys.exit(1)

        title, guid, raw_html, attachment_count = note_info
        print(f"Found: {title}")
        print(f"Attachments: {attachment_count}")

        # Step 2: Clean HTML
        html = clean_html(raw_html)

        # Step 3: Export and embed images
        img_files = []
        if attachment_count > 0:
            img_dir = tempfile.mkdtemp(prefix='ynote_imgs_')
            img_files, hash_map = export_attachments(keyword, img_dir)
            print(f"Exported {len(img_files)} images")
            if img_files:
                html = embed_images(html, img_files, hash_map)

        # Step 4: Build final HTML
        full_html = build_clean_html(html, note_title=title)

        html_path = tempfile.mktemp(suffix='.html')
        with open(html_path, 'w', encoding='utf-8') as f:
            f.write(full_html)

        # Step 5: Print to PDF
        if args.output:
            pdf_path = args.output
        else:
            safe_title = re.sub(r'[^\w\s-]', '', title).strip()[:50]
            pdf_path = os.path.expanduser(f'~/Downloads/{safe_title}.pdf')

        print(f"Generating PDF: {pdf_path}")
        success = chrome_print_to_pdf(html_path, pdf_path)
        if not success:
            print("ERROR: Chrome headless PDF generation failed")
            os.unlink(html_path)
            sys.exit(1)

        # Step 6: Remove blank pages
        remove_blank_pages(pdf_path)

        # Report
        size_kb = os.path.getsize(pdf_path) // 1024
        print(f"Done: {pdf_path} ({size_kb}KB)")

        # Cleanup
        os.unlink(html_path)
        for f in img_files:
            try:
                os.unlink(f)
            except OSError:
                pass

    finally:
        # Always clean up image temp dir
        if img_dir and os.path.isdir(img_dir):
            shutil.rmtree(img_dir, ignore_errors=True)
            print(f"  Cleaned up: {img_dir}")


if __name__ == '__main__':
    main()
