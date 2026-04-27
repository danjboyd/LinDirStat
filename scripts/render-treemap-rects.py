#!/usr/bin/env python3
import json
import math
import sys
from pathlib import Path


PALETTE = [
    (33, 120, 201), (222, 77, 56), (46, 158, 89), (240, 176, 51),
    (140, 89, 179), (0, 148, 148), (191, 79, 140), (107, 107, 107),
]


def stable_hash(text):
    value = 5381
    for ch in text:
        value = ((value << 5) + value) + ord(ch)
    return value


def color_for_ext(ext):
    return PALETTE[stable_hash(ext or "<none>") % len(PALETTE)]


def write_ppm(path, pixels, width, height):
    with open(path, "wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        f.write(bytes(channel for pixel in pixels for channel in pixel))


def main():
    if len(sys.argv) != 5:
        print("usage: render-treemap-rects.py rects.json width height output.ppm", file=sys.stderr)
        return 2
    rects_path = Path(sys.argv[1])
    width = int(sys.argv[2])
    height = int(sys.argv[3])
    output_path = Path(sys.argv[4])
    items = json.loads(rects_path.read_text())
    pixels = [(0, 0, 0)] * (width * height)
    for item in items:
        x, y, w, h = item["rect"]
        x0 = max(0, int(math.floor(x)) + 1)
        y0 = max(0, int(math.floor(y)) + 1)
        x1 = min(width, int(math.ceil(x + w)) - 1)
        y1 = min(height, int(math.ceil(y + h)) - 1)
        color = color_for_ext(item.get("ext"))
        for py in range(y0, y1):
            row = py * width
            for px in range(x0, x1):
                pixels[row + px] = color
    write_ppm(output_path, pixels, width, height)
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
