#!/usr/bin/env python3
"""Normalize the stage 03 parallax layers and build a static review preview."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def clean_layer(path: Path, minimum_area: int = 900) -> Image.Image:
    pixels = np.asarray(Image.open(path).convert("RGBA")).copy()
    alpha = pixels[..., 3]
    labels, _ = ndimage.label(alpha >= 20)
    sizes = np.bincount(labels.ravel())
    keep_ids = np.flatnonzero(sizes >= minimum_area)
    keep_ids = keep_ids[keep_ids != 0]
    keep = np.isin(labels, keep_ids)
    keep = ndimage.binary_dilation(keep, iterations=2)
    pixels[..., 3] = np.where(keep, alpha, 0)
    image = Image.fromarray(pixels, "RGBA")
    image.save(path, optimize=True)
    return image


def fit_bottom(image: Image.Image, canvas: tuple[int, int], height_fraction: float,
               opacity: float) -> Image.Image:
    target_h = int(canvas[1] * height_fraction)
    target_w = round(image.width * target_h / image.height)
    layer = image.resize((target_w, target_h), Image.Resampling.LANCZOS)
    if opacity < 1.0:
        layer.putalpha(layer.getchannel("A").point(lambda value: round(value * opacity)))
    out = Image.new("RGBA", canvas)
    x = (canvas[0] - target_w) // 2
    out.alpha_composite(layer, (x, canvas[1] - target_h))
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()

    sky = Image.open(args.folder / "sky.png").convert("RGBA")
    layers = {
        "city_far.png": clean_layer(args.folder / "city_far.png"),
        "festival_mid.png": clean_layer(args.folder / "festival_mid.png"),
        "festival_near.png": clean_layer(args.folder / "festival_near.png"),
    }
    sky.convert("RGB").save(args.folder / "sky.png", optimize=True)

    if args.preview is not None:
        preview = sky.copy()
        preview.alpha_composite(fit_bottom(layers["city_far.png"], sky.size, 0.60, 0.82))
        preview.alpha_composite(fit_bottom(layers["festival_mid.png"], sky.size, 0.50, 0.80))
        preview.alpha_composite(fit_bottom(layers["festival_near.png"], sky.size, 0.24, 0.82))
        preview.convert("RGB").save(args.preview, quality=92)


if __name__ == "__main__":
    main()
