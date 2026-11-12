#!/usr/bin/env python3
"""匯出後處理：把 music_picker.js 嵌進 index.html，並打成 itch 用 zip。"""
from __future__ import annotations

import shutil
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "build" / "web"
JS = ROOT / "scripts" / "web" / "music_picker.js"
MARKER = "<!-- jump-music-picker -->"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")


def inject_picker(html_path: Path, js_path: Path) -> None:
    html = html_path.read_text(encoding="utf-8")
    js = js_path.read_text(encoding="utf-8")
    block = f"{MARKER}\n<script>\n{js}\n</script>\n"
    if MARKER in html:
        start = html.index(MARKER)
        # Replace previous injected block through its closing script tag.
        end = html.index("</script>", start) + len("</script>")
        html = html[:start] + block.rstrip() + html[end:]
    else:
        if "</head>" not in html:
            raise SystemExit("index.html 沒有 </head>")
        html = html.replace("</head>", block + "</head>", 1)
    html_path.write_text(html, encoding="utf-8")
    # 也放一份同目錄，方便除錯
    shutil.copy2(js_path, WEB / "music_picker.js")


def export_web() -> None:
    if not GODOT.is_file():
        raise SystemExit(f"找不到 Godot：{GODOT}")
    WEB.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(GODOT),
        "--headless",
        "--path",
        str(ROOT),
        "--export-release",
        "Web",
        str(WEB / "index.html"),
    ]
    print("匯出中：", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def make_zip() -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M")
    out = ROOT / "build" / f"heart_beat_web_{stamp}.zip"
    if out.exists():
        out.unlink()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(WEB.iterdir()):
            if path.is_file():
                zf.write(path, arcname=path.name)
    # 同步一份固定檔名，方便辨認
    latest = ROOT / "build" / "heart_beat_web_latest.zip"
    shutil.copy2(out, latest)
    return out


def main() -> None:
    do_export = "--skip-export" not in sys.argv
    if do_export:
        export_web()
    if not (WEB / "index.html").is_file():
        raise SystemExit("找不到 build/web/index.html，請先匯出 Web")
    if not JS.is_file():
        raise SystemExit(f"找不到 {JS}")
    inject_picker(WEB / "index.html", JS)
    # 確認字串有進 pck（新錯誤文案）
    pck = (WEB / "index.pck").read_bytes()
    if "網頁選檔元件未載入".encode("utf-8") not in pck and "JumpMusicPicker".encode("utf-8") not in pck:
        print("警告：index.pck 可能仍是舊包（找不到新字串）", flush=True)
    else:
        print("index.pck 已含新選檔相關字串", flush=True)
    if MARKER not in (WEB / "index.html").read_text(encoding="utf-8"):
        raise SystemExit("注入 music picker 失敗")
    z = make_zip()
    print(f"完成：上傳這個 zip 到 itch → {z}")
    print(f"或固定檔名：{ROOT / 'build' / 'heart_beat_web_latest.zip'}")


if __name__ == "__main__":
    main()
