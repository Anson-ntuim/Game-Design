"""把手繪 Logo（白底 JPG）去背、加貼紙白邊，輸出 assets/ui/logo.png。
用法：python3 tools/make_logo.py assets/source/logo_drawing.jpg assets/ui/logo.png 預覽.png
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage as nd
src, out, preview = sys.argv[1:4]
im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
lum = im.mean(axis=2)
sat = im.max(axis=2) - im.min(axis=2)
light = (lum > 214) & (sat < 30)
## 筆畫有小缺口時背景會漏進臉和大鼓：先把深色筆畫加粗 2px 補起來，只拿來判斷連通
dark = ~light
closed = nd.binary_dilation(dark, iterations=2)
region = light & ~closed
lab, n = nd.label(region)
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(border))
## 補回加粗時吃掉的背景邊緣：和背景相連的淺色像素也算背景
bg = nd.binary_propagation(bg, mask=light)
## 字和線條圍起來的小白洞（例如「菜人尾狗」的字框裡）也挖掉
lab2, n2 = nd.label(light & ~bg)
sizes = nd.sum(np.ones_like(lab2), lab2, range(1, n2 + 1))
small = np.isin(lab2, [i + 1 for i, s in enumerate(sizes) if s < 160])
bg |= small
## 細長的白條（鈸架兩條線中間）也是背景
objs = nd.find_objects(lab2)
for i, sl in enumerate(objs):
    if sl is None:
        continue
    h = sl[0].stop - sl[0].start
    w = sl[1].stop - sl[1].start
    if max(h, w) > 120 and min(h, w) < 34:
        bg |= lab2 == (i + 1)
alpha = np.where(bg, 0.0, 1.0)
## 背景旁邊 2px 的淡色描邊：依深淺給半透明，避免在深色背景上出現白邊
near = nd.binary_dilation(bg, iterations=2) & ~bg
soft = np.clip((255.0 - lum) / 110.0, 0.0, 1.0)
alpha = np.where(near, np.minimum(alpha, soft), alpha)
rgb = im.copy()
## 半透明像素把白色去掉（反推前景色）
a = np.clip(alpha, 1e-3, 1.0)[..., None]
rgb = np.where(near[..., None], np.clip((im - 255.0 * (1 - a)) / a, 0, 255), rgb)
## 貼紙白邊：在圖案外圍墊一圈白色，深色背景上鉛筆線和字才看得清楚
solid = alpha > 0.35
rim = nd.binary_dilation(solid, iterations=7)
rim = nd.binary_fill_holes(rim) & rim
rim_soft = nd.gaussian_filter(rim.astype(np.float32), 1.2)
base = np.dstack([np.full_like(lum, 255.0)] * 3)
out_a = np.clip(np.maximum(alpha, rim_soft), 0, 1)
out_rgb = rgb * alpha[..., None] + base * (1 - alpha[..., None])
rgba = np.dstack([out_rgb, out_a * 255.0]).astype(np.uint8)
img = Image.fromarray(rgba, "RGBA")
bbox = img.getbbox()
img = img.crop((max(0, bbox[0] - 8), max(0, bbox[1] - 8), min(img.width, bbox[2] + 8), min(img.height, bbox[3] + 8)))
img.save(out)
bgc = Image.new("RGBA", img.size, (26, 16, 54, 255))
bgc.alpha_composite(img)
bgc.convert("RGB").save(preview)
print(img.size, "removed", int(bg.sum()), "px")
