#!/usr/bin/env python3
"""Draw LinDirStat's Linux app icon (256x256 PNG).

A port of macos/icon/make-icon.swift: a cushion treemap in WinDirStat's
colours on a rounded square. The output is committed as
Source/Resources/LinDirStat.png (the bundle's NSIcon, and the AppImage's
icon); rerun this only to change the artwork.

Usage: make-linux-icon.py out.png   (needs Pillow and NumPy)
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCALE = 4
SIZE = 256 * SCALE

PALETTE = [(64, 96, 255), (255, 64, 64), (64, 220, 64), (255, 220, 0),
           (0, 210, 230), (230, 0, 230), (255, 150, 20), (140, 140, 160)]


def cells(x0, y0, w, h):
    """The fixed treemap layout from the macOS icon, in top-down coordinates."""
    out = []

    def add(x, y_up, cw, ch, colour):
        # The Swift source measures y upwards from the bottom of the body.
        out.append(((x, y0 + h - (y_up - y0) - ch, cw, ch), colour))

    left_w = w * 0.56
    add(x0, y0 + h * 0.42, left_w, h * 0.58, 0)
    add(x0, y0, left_w * 0.58, h * 0.42, 1)
    add(x0 + left_w * 0.58, y0 + h * 0.18, left_w * 0.42, h * 0.24, 3)
    add(x0 + left_w * 0.58, y0, left_w * 0.42, h * 0.18, 5)
    rx, rw = x0 + left_w, w - left_w
    add(rx, y0 + h * 0.64, rw, h * 0.36, 2)
    add(rx, y0 + h * 0.36, rw * 0.55, h * 0.28, 4)
    add(rx + rw * 0.55, y0 + h * 0.36, rw * 0.45, h * 0.28, 6)
    small_h = h * 0.36
    sx = rx
    for i, fraction in enumerate([0.30, 0.22, 0.18, 0.12, 0.10, 0.08]):
        cw = rw * fraction
        rows = 2 if i < 2 else 3
        rh = small_h / rows
        for j in range(rows):
            add(sx, y0 + j * rh, cw, rh, (i * 3 + j + 1) % len(PALETTE))
        sx += cw
    return out


def cushion(pixels, rect, colour):
    """WinDirStat-style shading: light up and to the left, dark at the edges."""
    x, y, w, h = rect
    x1, y1 = int(round(x)), int(round(y))
    x2, y2 = int(round(x + w)), int(round(y + h))
    if x2 <= x1 or y2 <= y1:
        return
    c = np.array(colour, dtype=float) / 255.0
    light = np.minimum(1.0, c * 1.25 + 0.25)
    dark = c * 0.35
    cx, cy = x + w * 0.38, y + h * 0.38
    radius = max(w, h) * 0.78
    ys, xs = np.mgrid[y1:y2, x1:x2]
    t = np.clip(np.hypot(xs - cx, ys - cy) / radius, 0.0, 1.0)[..., None]
    first = light + (c - light) * (t / 0.55)
    second = c + (dark - c) * ((t - 0.55) / 0.45)
    pixels[y1:y2, x1:x2, :3] = np.where(t < 0.55, first, second) * 255.0


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "lindirstat.png"
    margin = 100 * SIZE // 1024
    body = (margin, margin, SIZE - margin, SIZE - margin)
    radius = 185 * SIZE // 1024

    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(body, radius=radius, fill=255)

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        (body[0], body[1] + 10 * SCALE // 4, body[2], body[3] + 10 * SCALE // 4),
        radius=radius, fill=90)
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(14 * SCALE // 4)))

    pixels = np.zeros((SIZE, SIZE, 4), dtype=float)
    pixels[..., :3] = (26, 28, 36)
    pixels[..., 3] = 255
    body_w = body[2] - body[0]
    layout = cells(body[0], body[1], body_w, body_w)
    for rect, colour in layout:
        cushion(pixels, rect, PALETTE[colour])
    art = Image.fromarray(pixels.astype(np.uint8), "RGBA")

    draw = ImageDraw.Draw(art)
    for (x, y, w, h), _ in layout:
        draw.rectangle((x, y, x + w, y + h), outline=(13, 13, 13, 217), width=5 * SCALE // 4)

    icon = Image.alpha_composite(Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), shadow)
    clipped = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    clipped.paste(art, (0, 0), mask)
    icon = Image.alpha_composite(icon, clipped)
    ImageDraw.Draw(icon).rounded_rectangle(body, radius=radius, outline=(255, 255, 255, 31), width=3 * SCALE // 4)

    icon.resize((256, 256), Image.LANCZOS).save(out)


if __name__ == "__main__":
    main()
