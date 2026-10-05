"""從角色三視圖裁出遊戲內用的側面圖（面向右、腳貼底、去掉透明邊）。

用法：python3 tools/make_skins.py
輸入：assets/白狗三視圖角色參考表.png（左邊第一個是側面）
輸出：assets/characters/dog_side.png（高 HEIGHT px，遊戲裡再縮小成約 60px 高）
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "白狗三視圖角色參考表.png"
OUT = ROOT / "assets" / "characters" / "dog_side.png"
HEIGHT = 192


def column_spans(im: Image.Image) -> list[tuple[int, int]]:
    alpha = im.getchannel("A")
    w, h = im.size
    filled = [any(alpha.getpixel((x, y)) > 16 for y in range(0, h, 2)) for x in range(w)]
    spans, start = [], None
    for x, f in enumerate(filled + [False]):
        if f and start is None:
            start = x
        elif not f and start is not None:
            if x - start > 20:
                spans.append((start, x))
            start = None
    return spans


im = Image.open(SRC).convert("RGBA")
x0, x1 = column_spans(im)[0]
side = im.crop((x0, 0, x1, im.height))
side = side.crop(side.getchannel("A").point(lambda a: 255 if a > 16 else 0).getbbox())
scale = HEIGHT / side.height
side = side.resize((round(side.width * scale), HEIGHT), Image.LANCZOS)
OUT.parent.mkdir(parents=True, exist_ok=True)
side.save(OUT)
print(f"wrote {OUT} {side.size}")
