"""把生成的狗狗動作圖切成遊戲用的動作幀：assets/characters/dog/<動作>_<n>.png。

每張來源圖是一排透明背景的動作，用透明的空隙切開。
各張圖的比例不同，用爆炸頭（最大一塊黑色）的面積統一成和 dog_side.png（高 192 px）一樣大；
左右用爆炸頭對齊（原地動作 FEET_ALIGNED 用腳底中心）；站在地上的動作上下貼齊腳底，空中的動作（縮腳、橫躺）上下置中在站姿的中心。
每一幀輸出成同樣大小的畫布，腳底中心固定在 ANCHOR，player.gd 的 draw_skin 照這個點對齊。

用法：python3 tools/make_dog_frames.py [--preview]
--preview 另外輸出 /tmp/dog_frames_preview.png（所有幀排在一起、畫出腳底線）方便檢查。
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
REF = ASSETS / "characters" / "dog_side.png"
OUT = ASSETS / "characters" / "dog"
## 改這兩個要同步改 game_state.gd 的 SKINS（frame_anchor）
CANVAS = (448, 320)
ANCHOR = (224, 280)

## (來源圖, [(輸出名, 是否站在地上), ...])，順序和圖裡由左到右相同
SHEETS = [
    ("六格奔跑小狗鼓手精靈圖.png", [(f"run_{i}", True) for i in range(6)]),
    ("小狗跳躍雙格動畫-2.png", [("jump_0", False), ("fall_0", False)]),
    ("小狗側身雙連跳擊鼓-5.png", [("orb_0", False), ("orb_1", False)]),
    ("小狗牆滑、落地、跌倒-6.png", [("wall_0", False), ("land_0", True), ("hurt_0", False)]),
    ("小狗鼓手六格律動-1.png", [(f"idle_{i}", True) for i in range(6)]),
    ("小狗三段起跑動作表-2.png", [("stop_0", True), ("stop_1", True), ("start_0", True)]),
    ("小狗落地回彈動作表-3.png", [("land_1", True), ("land_2", True)]),
    ("爆炸頭小狗躍起瞬間-4.png", [("apex_0", False)]),
    ("小狗三格衝刺分鏡-5.png", [("dash_0", False), ("dash_1", False), ("dash_2", False)]),
]
## 原地動作左右改用腳底中心對齊：頭會前後晃，用爆炸頭對齊的話腳會滑來滑去
FEET_ALIGNED = {f"idle_{i}" for i in range(6)} | {"land_1", "land_2", "stop_1"}


def column_spans(alpha):
    cols = (alpha > 16).any(axis=0)
    spans, start = [], None
    for x, filled in enumerate(list(cols) + [False]):
        if filled and start is None:
            start = x
        elif not filled and start is not None:
            if x - start > 20:
                spans.append((start, x))
            start = None
    return spans


def split_touching(alpha, spans, n):
    """有幾幀黏在一起（鼓棒碰到隔壁的耳朵）時，在最寬那段中間 30%～70% 不透明最少的那一欄切開"""
    cols = (alpha > 16).sum(axis=0)
    while len(spans) < n:
        i = max(range(len(spans)), key=lambda k: spans[k][1] - spans[k][0])
        x0, x1 = spans[i]
        a, b = x0 + (x1 - x0) * 3 // 10, x0 + (x1 - x0) * 7 // 10
        cut = a + int(np.argmin(cols[a:b]))
        spans[i:i + 1] = [(x0, cut), (cut, x1)]
    return spans


def drop_cut_scraps(im):
    """切開的地方會留下隔壁幀的碎片：貼著左右邊緣、又比本體小很多的那幾塊拿掉"""
    rgba = np.array(im)
    labels, n = ndimage.label(rgba[:, :, 3] > 16)
    if n <= 1:
        return im
    sizes = ndimage.sum(np.ones_like(labels), labels, range(1, n + 1))
    for k in range(1, n + 1):
        cols = np.where((labels == k).any(axis=0))[0]
        on_edge = cols[0] == 0 or cols[-1] == rgba.shape[1] - 1
        if on_edge and sizes[k - 1] < 0.02 * sizes.max():
            rgba[labels == k, 3] = 0
    return Image.fromarray(rgba)


def afro(rgba):
    """最大一塊深色（爆炸頭）的面積與重心；眼睛、鼻子也是黑的，但都是小塊"""
    a = rgba[:, :, 3] > 200
    dark = a & (rgba[:, :, :3].max(axis=2) < 70)
    labels, n = ndimage.label(dark)
    assert n > 0, "找不到爆炸頭"
    sizes = ndimage.sum(dark, labels, range(1, n + 1))
    k = int(np.argmax(sizes)) + 1
    cy, cx = ndimage.center_of_mass(labels == k)
    return float(sizes[k - 1]), cx, cy


def trim(im):
    box = im.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    return im.crop(box)


ref = trim(Image.open(REF).convert("RGBA"))
ref_area, ref_cx, ref_cy = afro(np.array(ref))
## 腳底中心在爆炸頭重心右邊幾 px（dog_side.png 的站姿）
DX = ref.width * 0.5 - ref_cx

OUT.mkdir(parents=True, exist_ok=True)
frames = []
for src, names in SHEETS:
    sheet = Image.open(ASSETS / src).convert("RGBA")
    alpha = np.array(sheet)[:, :, 3]
    spans = split_touching(alpha, column_spans(alpha), len(names))
    assert len(spans) == len(names), (src, spans)
    crops = [trim(drop_cut_scraps(sheet.crop((x0, 0, x1, sheet.height)))) for x0, x1 in spans]
    infos = [afro(np.array(c)) for c in crops]
    scale = (ref_area / np.mean([i[0] for i in infos])) ** 0.5
    for (name, grounded), crop, (_, cx, _) in zip(names, crops, infos):
        w, h = round(crop.width * scale), round(crop.height * scale)
        img = crop.resize((w, h), Image.LANCZOS)
        feet_x = cx * scale + DX
        if name in FEET_ALIGNED:
            a = np.array(img)[:, :, 3] > 16
            xs = np.where(a[h - 15:].any(axis=0))[0]
            feet_x = (xs[0] + xs[-1]) * 0.5
        feet_y = h if grounded else (h + ref.height) * 0.5
        left, top = round(ANCHOR[0] - feet_x), round(ANCHOR[1] - feet_y)
        assert left >= 0 and top >= 0 and left + w <= CANVAS[0] and top + h <= CANVAS[1], \
            (name, "超出畫布", left, top, left + w, top + h)
        canvas = Image.new("RGBA", CANVAS)
        canvas.paste(img, (left, top))
        canvas.save(OUT / f"{name}.png")
        frames.append((name, canvas))
        print(f"{name:8s} 縮放 {scale:.3f}  {w}x{h}  位置 ({left}, {top})")
print(f"wrote {len(frames)} frames → {OUT.relative_to(ROOT)}")

if "--preview" in sys.argv:
    cols = 6
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGBA", (CANVAS[0] * cols, CANVAS[1] * rows), (40, 48, 80, 255))
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(frames):
        x, y = (i % cols) * CANVAS[0], (i // cols) * CANVAS[1]
        sheet.alpha_composite(im, (x, y))
        d.line((x, y + ANCHOR[1], x + CANVAS[0], y + ANCHOR[1]), fill=(255, 200, 80, 255))
        d.line((x + ANCHOR[0], y + ANCHOR[1] - 8, x + ANCHOR[0], y + ANCHOR[1] + 8), fill=(255, 80, 80, 255))
        d.rectangle((x, y, x + CANVAS[0] - 1, y + CANVAS[1] - 1), outline=(90, 100, 140, 255))
        d.text((x + 6, y + 6), name, fill=(255, 255, 255, 255))
    sheet.save("/tmp/dog_frames_preview.png")
    print("preview /tmp/dog_frames_preview.png")
