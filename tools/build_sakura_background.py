#!/usr/bin/env python3
"""Normalize Sakura Park layers and prepare independently animated elements."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage


def clean_alpha(image: Image.Image, threshold: int = 16) -> Image.Image:
    pixels = np.asarray(image.convert("RGBA")).copy()
    alpha = pixels[..., 3]
    pixels[..., 3] = np.where(alpha < threshold, 0, alpha)
    return Image.fromarray(pixels, "RGBA")


def clean_cloud_layer(source: Path, output: Path, minimum_area: int = 800,
                      max_center_y: float | None = None) -> None:
    """Remove disconnected generation speckles while preserving soft cloud edges."""
    pixels = np.asarray(Image.open(source).convert("RGBA")).copy()
    alpha = pixels[..., 3]
    labels, count = ndimage.label(alpha >= 24)
    sizes = np.bincount(labels.ravel())
    keep_ids = np.flatnonzero(sizes >= minimum_area)
    keep_ids = keep_ids[keep_ids != 0]
    if max_center_y is not None:
        centers = ndimage.center_of_mass(alpha, labels, keep_ids)
        keep_ids = np.asarray([
            label_id for label_id, center in zip(keep_ids, centers)
            if center[0] < max_center_y
        ], dtype=int)
    keep = np.isin(labels, keep_ids)
    keep = ndimage.binary_dilation(keep, iterations=2)
    pixels[..., 3] = np.where(keep, alpha, 0)
    Image.fromarray(pixels, "RGBA").save(output, optimize=True)


def prepare_wheel(source: Path, output: Path) -> None:
    wheel = clean_alpha(Image.open(source))
    bbox = wheel.getbbox()
    if bbox is None:
        raise ValueError(f"wheel image has no visible pixels: {source}")
    wheel = wheel.crop(bbox)
    side = max(wheel.size)
    square = Image.new("RGBA", (side, side))
    square.alpha_composite(wheel, ((side - wheel.width) // 2, (side - wheel.height) // 2))
    square.resize((512, 512), Image.Resampling.LANCZOS).save(
        output / "ferris_wheel.png", optimize=True)


def remove_baked_wheel(source: Path, output: Path) -> None:
    """Fade the baked wheel out while keeping its distant hills as much as possible."""
    image = clean_alpha(Image.open(source))
    fade = Image.new("L", image.size)
    draw = ImageDraw.Draw(fade)
    draw.ellipse((405, 260, 835, 715), fill=255)
    fade = fade.filter(ImageFilter.GaussianBlur(18))
    pixels = np.asarray(image).copy()
    alpha = pixels[..., 3].astype(np.float32)
    pixels[..., 3] = np.clip(alpha * (1.0 - np.asarray(fade) / 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(pixels, "RGBA").save(output / "park_far_clean.png", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--wheel", type=Path)
    parser.add_argument("--sky-clean", type=Path)
    parser.add_argument("--clouds-far", type=Path)
    parser.add_argument("--clouds-near", type=Path)
    args = parser.parse_args()

    image = clean_alpha(Image.open(args.source))

    for name in ("park_far.png", "trees_mid.png"):
        path = args.output / name
        if path.exists():
            clean_alpha(Image.open(path)).save(path, optimize=True)
    remove_baked_wheel(args.output / "park_far.png", args.output)
    if args.wheel is not None:
        prepare_wheel(args.wheel, args.output)
    if args.sky_clean is not None:
        Image.open(args.sky_clean).convert("RGB").save(args.output / "sky_clean.png", optimize=True)
    if args.clouds_far is not None:
        clean_cloud_layer(args.clouds_far, args.output / "clouds_far.png")
    if args.clouds_near is not None:
        # Keep the two upper cloud groups; lower groups crowd the play space.
        clean_cloud_layer(args.clouds_near, args.output / "clouds_near.png",
                          max_center_y=430.0)
    image.save(args.source, optimize=True)
    pixels = np.asarray(image).copy()
    bottom = pixels.copy()
    bottom[:250, :, 3] = 0

    args.output.mkdir(parents=True, exist_ok=True)
    Image.fromarray(bottom, "RGBA").save(args.output / "park_near_bottom.png", optimize=True)


if __name__ == "__main__":
    main()
