#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path


def image_info(path):
    if not path or not Path(path).exists():
        return None
    try:
        completed = subprocess.run(
            ["identify", "-format", "%w %h %m", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        width, height, fmt = completed.stdout.strip().split(maxsplit=2)
        return {"path": str(path), "width": int(width), "height": int(height), "format": fmt}
    except Exception as exc:
        return {"path": str(path), "error": str(exc)}


def nearest_viewport(width, height, results):
    if not width or not height:
        return None
    return min(
        results,
        key=lambda result: abs(result["size"][0] - width) + abs(result["size"][1] - height),
        default=None,
    )


def main():
    if len(sys.argv) != 4:
        print("usage: gui-parity-correlation.py parity-summary.json screenshot-or-none output.json", file=sys.stderr)
        return 2
    summary_path = Path(sys.argv[1])
    screenshot_arg = None if sys.argv[2] == "-" else Path(sys.argv[2])
    output_path = Path(sys.argv[3])

    summary = json.loads(summary_path.read_text())
    screenshot = image_info(screenshot_arg)
    nearest = nearest_viewport(
        screenshot.get("width") if screenshot else None,
        screenshot.get("height") if screenshot else None,
        summary.get("results", []),
    )
    result = {
        "parity_summary": str(summary_path),
        "screenshot": screenshot,
        "nearest_headless_result": nearest,
        "notes": [
            "Use headless parity metrics for precise treemap failures.",
            "Use the GUI screenshot for whole-window pane placement, labels, and control overlap.",
        ],
    }
    output_path.write_text(json.dumps(result, indent=2))
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
