#!/usr/bin/env python3
"""Renders the Adwaita symbolic icons LinDirStat uses into PNG resources.

The Adwaita GNUstep theme tints images whose names end in "-symbolic" with
the surrounding text colour, as GTK does, so only the shapes matter. Icons
come from the system's Adwaita icon theme (LGPL-3 or CC-BY-SA-3.0); see
Source/Resources/Icons/README.md. Run again after changing ICONS.
"""
import sys
from pathlib import Path

import cairo
import gi

gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg  # noqa: E402

ADWAITA = Path("/usr/share/icons/Adwaita/symbolic")
ICONS = [
    "document-open-symbolic",
    "view-refresh-symbolic",
    "process-stop-symbolic",
    "zoom-in-symbolic",
    "zoom-out-symbolic",
    "zoom-original-symbolic",
    "go-up-symbolic",
    "edit-copy-symbolic",
    "folder-symbolic",
    "text-x-generic-symbolic",
    "insert-link-symbolic",
    "drive-harddisk-symbolic",
    "computer-symbolic",
    "system-search-symbolic",
    "user-trash-symbolic",
    "media-playback-pause-symbolic",
    "media-playback-start-symbolic",
    "radio-symbolic",
    "dialog-question-symbolic",
    "go-bottom-symbolic",
    "edit-clear-all-symbolic",
]


def find(name):
    matches = sorted(ADWAITA.glob(f"*/{name}.svg"))
    if not matches:
        sys.exit(f"missing icon: {name}")
    return matches[0]


def render(svg, size, out):
    handle = Rsvg.Handle.new_from_file(str(svg))
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    context = cairo.Context(surface)
    viewport = Rsvg.Rectangle()
    viewport.x, viewport.y, viewport.width, viewport.height = 0, 0, size, size
    handle.render_document(context, viewport)
    surface.write_to_png(str(out))


def main():
    out_dir = Path(__file__).resolve().parents[1] / "Source/Resources/Icons"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in ICONS:
        svg = find(name)
        render(svg, 16, out_dir / f"{name}.png")
        render(svg, 32, out_dir / f"{name}@2x.png")
        print(f"{name}: {svg}")


if __name__ == "__main__":
    main()
