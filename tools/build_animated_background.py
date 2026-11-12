#!/usr/bin/env python3
"""Normalize the animated Heartbeat City pilot layers for Godot."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


CANVAS = (1672, 941)


def fit_layer(
    source: Path, target: Path, size: tuple[int, int], y: int, x: int | None = None
) -> None:
    layer = Image.open(source).convert("RGBA").resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    left = (CANVAS[0] - size[0]) // 2 if x is None else x
    canvas.alpha_composite(layer, (left, y))
    canvas.save(target, optimize=True)


def window_glow(source: Path, target: Path) -> None:
    image = Image.open(source).convert("RGBA")
    data = np.asarray(image).astype(np.float32)
    rgb = data[..., :3]
    source_alpha = data[..., 3] / 255.0
    luminance = rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114
    warm = np.clip((rgb[..., 0] - rgb[..., 2] - 18.0) / 75.0, 0.0, 1.0)
    bright = np.clip((luminance - 125.0) / 95.0, 0.0, 1.0)
    alpha = source_alpha * warm * bright
    glow = np.zeros_like(data, dtype=np.uint8)
    glow[..., 0] = 255
    glow[..., 1] = 190
    glow[..., 2] = 128
    glow[..., 3] = np.clip(alpha * 255.0, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(glow, "RGBA").save(target, optimize=True)


def cloud_depth_layers(source: Path, far_target: Path, near_target: Path) -> None:
    clouds = Image.open(source).convert("RGBA")
    pixels = np.asarray(clouds).copy()
    alpha = pixels[..., 3]
    search = alpha[300:520, :540]
    seed_y, seed_x = np.unravel_index(int(search.argmax()), search.shape)
    seed = (int(seed_y + 300), int(seed_x))
    component = np.zeros(alpha.shape, dtype=bool)
    pending = deque([seed])
    component[seed] = True
    while pending:
        y, x = pending.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < alpha.shape[0] and 0 <= nx < alpha.shape[1]:
                if not component[ny, nx] and alpha[ny, nx] > 4:
                    component[ny, nx] = True
                    pending.append((ny, nx))

    far_pixels = pixels.copy()
    far_pixels[~component, 3] = 0
    near_pixels = pixels.copy()
    near_pixels[component, 3] = 0
    isolated = Image.fromarray(far_pixels, "RGBA")
    bbox = isolated.getbbox()
    far = Image.new("RGBA", clouds.size, (0, 0, 0, 0))
    if bbox is not None:
        far.alpha_composite(isolated.crop(bbox), (bbox[0], max(0, bbox[1] - 90)))
    near = Image.fromarray(near_pixels, "RGBA")
    far.save(far_target, optimize=True)
    near.save(near_target, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sky", type=Path, required=True)
    parser.add_argument("--clouds", type=Path, required=True)
    parser.add_argument("--moon", type=Path, required=True)
    parser.add_argument("--stars", type=Path, required=True)
    parser.add_argument("--city-far", type=Path, required=True)
    parser.add_argument("--city-near", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    Image.open(args.sky).convert("RGB").save(args.output / "sky_base.png", optimize=True)
    fit_layer(args.clouds, args.output / "clouds.png", (1672, 557), 42)
    cloud_depth_layers(
        args.output / "clouds.png",
        args.output / "clouds_far.png",
        args.output / "clouds_near.png",
    )
    fit_layer(args.stars, args.output / "stars.png", (1672, 557), 18)
    fit_layer(args.moon, args.output / "moon.png", (420, 280), 72, 790)
    window_glow(args.city_far, args.output / "city_far_glow.png")
    window_glow(args.city_near, args.output / "city_near_glow.png")


if __name__ == "__main__":
    main()
