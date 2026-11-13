"""Normalize the generated monkey strips into engine-ready character frames.

Run from the repository with a Python environment that has Pillow and NumPy:
    python3 tools/make_monkey_frames.py [--preview]

Outputs 448x320 RGBA frames under assets/characters/monkey and the 192px
fallback sprite assets/characters/monkey_side.png. All animated frames use the
same foot anchor as Player.draw_skin: (224, 280).
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "source" / "monkey"
OUT = ROOT / "assets" / "characters" / "monkey"
STATIC_OUT = ROOT / "assets" / "characters" / "monkey_side.png"
CANVAS = (448, 320)
ANCHOR = (224, 280)
REF_HEIGHT = 192

SHEETS = [
    ("idle_strip.png", [f"idle_{i}" for i in range(6)], set()),
    ("run_strip.png", [f"run_{i}" for i in range(6)], set()),
    ("air_strip.png", ["jump_0", "apex_0", "fall_0"], {"jump_0", "apex_0", "fall_0"}),
    ("orb_strip.png", ["orb_0", "orb_1"], {"orb_0", "orb_1"}),
    ("wall_land_hurt_strip.png", ["wall_0", "land_0", "hurt_0"], {"wall_0"}),
    ("stop_start_strip.png", ["stop_0", "stop_1", "start_0"], set()),
    ("landing_recovery_strip.png", ["land_1", "land_2"], set()),
    ("dash_strip.png", ["dash_0", "dash_1", "dash_2"], {"dash_0", "dash_1", "dash_2"}),
]


def trim(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    box = alpha.point(lambda value: 255 if value > 16 else 0).getbbox()
    if box is None:
        raise ValueError("empty image")
    return image.crop(box)


def column_spans(image: Image.Image, expected: int) -> list[tuple[int, int]]:
    alpha = np.array(image.getchannel("A"))
    counts = (alpha > 16).sum(axis=0)
    filled = counts > 0
    spans: list[tuple[int, int]] = []
    start = None
    for x, has_pixel in enumerate(list(filled) + [False]):
        if has_pixel and start is None:
            start = x
        elif not has_pixel and start is not None:
            if x - start > 20:
                spans.append((start, x))
            start = None
    while len(spans) < expected:
        index = max(range(len(spans)), key=lambda i: spans[i][1] - spans[i][0])
        x0, x1 = spans[index]
        a = x0 + (x1 - x0) * 3 // 10
        b = x0 + (x1 - x0) * 7 // 10
        cut = a + int(np.argmin(counts[a:b]))
        spans[index:index + 1] = [(x0, cut), (cut, x1)]
    if len(spans) != expected:
        raise ValueError(f"expected {expected} frames, found {spans}")
    return spans


def hair_area(image: Image.Image) -> float:
    rgba = np.asarray(image)
    opaque = rgba[:, :, 3] > 180
    rgb = rgba[:, :, :3]
    dark = opaque & (rgb[:, :, 0] < 105) & (rgb[:, :, 1] < 80) & (rgb[:, :, 2] < 75)
    count = int(dark.sum())
    if count == 0:
        raise ValueError("no dark hair region")
    return float(count)


static = trim(Image.open(SOURCE / "static_source.png").convert("RGBA"))
static_scale = REF_HEIGHT / static.height
static = static.resize((round(static.width * static_scale), REF_HEIGHT), Image.Resampling.LANCZOS)
STATIC_OUT.parent.mkdir(parents=True, exist_ok=True)
static.save(STATIC_OUT)
reference_area = hair_area(static)

OUT.mkdir(parents=True, exist_ok=True)
frames: list[tuple[str, Image.Image]] = []
for filename, names, airborne in SHEETS:
    sheet = Image.open(SOURCE / filename).convert("RGBA")
    crops = [trim(sheet.crop((x0, 0, x1, sheet.height))) for x0, x1 in column_spans(sheet, len(names))]
    areas = [hair_area(crop) for crop in crops]
    scale = (reference_area / (sum(areas) / len(areas))) ** 0.5
    for name, crop in zip(names, crops):
        width, height = round(crop.width * scale), round(crop.height * scale)
        if width > CANVAS[0] - 16 or height > CANVAS[1] - 16:
            fit = min((CANVAS[0] - 16) / width, (CANVAS[1] - 16) / height)
            width, height = round(width * fit), round(height * fit)
        frame = crop.resize((width, height), Image.Resampling.LANCZOS)
        left = round(ANCHOR[0] - width * 0.5)
        top = round(ANCHOR[1] - ((height + REF_HEIGHT) * 0.5 if name in airborne else height))
        canvas = Image.new("RGBA", CANVAS)
        canvas.alpha_composite(frame, (left, top))
        canvas.save(OUT / f"{name}.png")
        frames.append((name, canvas))

print(f"wrote {len(frames)} frames -> {OUT.relative_to(ROOT)}")

if "--preview" in sys.argv:
    columns = 6
    rows = (len(frames) + columns - 1) // columns
    preview = Image.new("RGBA", (CANVAS[0] * columns, CANVAS[1] * rows), (36, 42, 66, 255))
    draw = ImageDraw.Draw(preview)
    for i, (name, frame) in enumerate(frames):
        x, y = (i % columns) * CANVAS[0], (i // columns) * CANVAS[1]
        preview.alpha_composite(frame, (x, y))
        draw.line((x, y + ANCHOR[1], x + CANVAS[0], y + ANCHOR[1]), fill=(255, 205, 90, 180))
        draw.text((x + 8, y + 8), name, fill="white")
    preview_path = Path("/tmp/monkey_frames_preview.png")
    preview.save(preview_path)
    print(f"preview {preview_path}")
