#!/usr/bin/env python3
"""Sync scripts/web/music_picker.js → music_picker_embed.gd（GDScript 字串需跳脫反斜線）。"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
js = (root / "scripts/web/music_picker.js").read_text()
# GDScript """...""" 會解析跳脫序列；JS 的 \. \/ 等必須寫成 \\.
escaped = js.replace("\\", "\\\\")
if '"""' in escaped:
    raise SystemExit('music_picker.js 含 """，無法嵌入')
out = root / "scripts/web/music_picker_embed.gd"
out.write_text(
    "extends RefCounted\n"
    "class_name MusicPickerEmbed\n"
    "## 與 music_picker.js 同步的內嵌來源；Web 匯出漏打 .js 時仍可 eval。\n"
    "## 修改選檔邏輯時請先改 music_picker.js，再跑：python3 tools/embed_music_picker.py\n\n"
    'const SOURCE := """\n' + escaped + '\n"""\n'
)
print(f"updated {out}")
