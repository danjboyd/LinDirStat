#!/usr/bin/env python3
"""WinDirStat treemap parity gate.

Renders each fixture tree twice:

* LinDirStat: the production LDTreemap layout and cushion renderer, invoked
  through Tools/windirstat-parity-exporter.
* Oracle: an independent Python port of WinDirStat's CTreeMap
  (references/WinDirStat/windirstat/Controls/TreeMap.cpp and TreeMap.h):
  KDirStat row layout, cushion shading, the equalized default palette and
  WinDirStat's rank-based extension colors.

Both use the same double-precision math, so the images are expected to match
pixel for pixel. Strict mode (the default) fails on any layout difference or
on pixel drift beyond the thresholds below.
"""
import json
import math
import os
import subprocess
import sys
from pathlib import Path

# TreeMap.h DefaultCushionColors.
DEFAULT_CUSHION_COLORS = [
    (0, 0, 255), (255, 0, 0), (0, 255, 0), (255, 255, 0),
    (0, 255, 255), (255, 0, 255), (255, 170, 0), (0, 85, 255),
    (255, 0, 85), (85, 255, 0), (170, 0, 255), (0, 255, 85),
    (255, 0, 170), (0, 170, 255), (255, 85, 0), (0, 255, 170),
    (85, 0, 255), (255, 255, 255),
]

# TreeMap.h DefaultOptions.
OPTIONS = {
    "brightness": 0.88,
    "height": 0.38,
    "scale_factor": 0.91,
    "ambient_light": 0.13,
    "light_x": -1.0,
    "light_y": -1.0,
}
PALETTE_BRIGHTNESS = 0.6
MIN_PROPORTION = 0.4

# TreeMap.h COLORFLAG_DARKER / COLORFLAG_LIGHTER.
COLORFLAG_DARKER = 0x01000000
COLORFLAG_LIGHTER = 0x02000000
COLORFLAG_MASK = 0x03000000

# Item.Extended.cpp CItem::GetGraphColor for <Unknown> and <Free Space>.
SPACE_COLORS = {
    "unknown": ((255, 255, 0), COLORFLAG_LIGHTER),
    "free": ((100, 100, 100), COLORFLAG_DARKER),
}

THRESHOLDS = {
    "exact_pixel_match_min": 0.999,
    "max_channel_delta_max": 2,
    "rect_mismatch_max": 0,
}


def c_div(a, b):
    """C integer division (truncates toward zero)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def distribute_first(first, second, third):
    h = c_div(first - 255, 2)
    first = 255
    second += h
    third += h
    if second > 255:
        j = second - 255
        second = 255
        third += j
    elif third > 255:
        j = third - 255
        third = 255
        second += j
    return first, second, third


def normalize_color(r, g, b):
    if r > 255:
        r, g, b = distribute_first(r, g, b)
    elif g > 255:
        g, r, b = distribute_first(g, r, b)
    elif b > 255:
        b, r, g = distribute_first(b, r, g)
    return r, g, b


def make_bright_color(rgb, brightness):
    dr, dg, db = (c / 255.0 for c in rgb)
    f = 3.0 * brightness / (dr + dg + db)
    dr *= f
    dg *= f
    db *= f
    return normalize_color(int(dr * 255), int(dg * 255), int(db * 255))


PALETTE = [make_bright_color(c, PALETTE_BRIGHTNESS) for c in DEFAULT_CUSHION_COLORS]


def extension_key(name):
    dot = name.rfind(".")
    if dot <= 0 or dot == len(name) - 1:
        return "<none>"
    return name[dot + 1:].lower()


def prepare(spec, parent_path=None):
    path = f"{parent_path}/{spec['name']}" if parent_path else spec["name"]
    node = {"name": spec["name"], "path": path}
    children = [prepare(child, path) for child in spec.get("children", [])]
    node["space"] = spec.get("space")
    if children:
        node["size"] = sum(child["size"] for child in children)
        node["is_file"] = False
    else:
        node["size"] = int(spec.get("size", 0))
        node["is_file"] = node["space"] is None
    node["children"] = sorted(children, key=lambda c: (-c["size"], c["name"]))
    return node


def collect_extensions(node, totals):
    if node["is_file"]:
        key = extension_key(node["name"])
        totals[key] = totals.get(key, 0) + node["size"]
        return
    for child in node["children"]:
        collect_extensions(child, totals)


def color_indexes(root):
    """DirStatDoc: rank extensions by bytes; ranks past the palette share the last color."""
    totals = {}
    collect_extensions(root, totals)
    ranked = sorted(totals.items(), key=lambda item: (-item[1], item[0]))
    return {key: min(rank, len(PALETTE) - 1) for rank, (key, _) in enumerate(ranked)}


def kdirstat_next_row(sizes, parent_size, next_child, width, child_width):
    size_used = 0.0
    row_height = 0.0
    i = next_child
    while i < len(sizes):
        child_size = sizes[i]
        size_used += child_size
        virtual_row_height = size_used / parent_size
        cw = child_size / parent_size * width / virtual_row_height
        if cw / virtual_row_height < MIN_PROPORTION and i > next_child:
            break
        row_height = virtual_row_height
        i += 1
    used = i - next_child
    for j in range(used):
        child_width[next_child + j] = sizes[next_child + j] / (parent_size * row_height)
    return row_height, used


def kdirstat_children(node, rect):
    left, top, right, bottom = rect
    children = [c for c in node["children"] if c["size"] > 0]
    sizes = [float(c["size"]) for c in children]
    parent_size = float(node["size"])
    pw, ph = right - left, bottom - top
    horizontal = pw >= ph
    width = 1.0
    if horizontal:
        if ph > 0:
            width = pw / ph
    elif pw > 0:
        width = ph / pw

    child_width = [0.0] * len(children)
    rows = []
    next_child = 0
    while next_child < len(children):
        row_height, used = kdirstat_next_row(sizes, parent_size, next_child, width, child_width)
        rows.append((row_height, used))
        next_child += used

    row_extent = ph if horizontal else pw
    child_extent = pw if horizontal else ph
    out = []
    f_top = float(top if horizontal else left)
    c = 0
    for row_index, (row_height, used) in enumerate(rows):
        f_bottom = f_top + row_height * row_extent
        row_bottom = int(f_bottom)
        if row_index == len(rows) - 1:
            row_bottom = bottom if horizontal else right
        f_left = float(left if horizontal else top)
        for k in range(used):
            f_right = f_left + child_width[c] * child_extent
            row_right = int(f_right)
            if k == used - 1:
                row_right = right if horizontal else bottom
            if horizontal:
                child_rect = (int(f_left), int(f_top), row_right, row_bottom)
            else:
                child_rect = (int(f_top), int(f_left), row_bottom, row_right)
            out.append((children[c], child_rect))
            f_left = f_right
            c += 1
        f_top = f_bottom
    return out


def add_ridge(rect, surface, h):
    left, top, right, bottom = rect
    width, height = right - left, bottom - top
    s = list(surface)
    h4 = 4.0 * h
    wf = h4 / width
    s[2] += wf * (right + left)
    s[0] -= wf
    hf = h4 / height
    s[3] += hf * (bottom + top)
    s[1] -= hf
    return s


def oracle_render(root, width, height):
    """Port of CTreeMap::DrawTreeMap for the default options (no grid)."""
    pixels = bytearray(width * height * 3)  # Grid color black.
    leaves = []
    indexes = color_indexes(root)

    lx, ly, lz = OPTIONS["light_x"], OPTIONS["light_y"], 10.0
    length = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / length, ly / length, lz / length
    ia = OPTIONS["ambient_light"]
    shading = 1.0 - ia

    def leaf_color(node):
        """CTreeMap::RenderRectangle: flagged colors are equalized and drawn darker or lighter."""
        if node["space"] is not None:
            rgb, flags = SPACE_COLORS[node["space"]]
            brightness = OPTIONS["brightness"]
            if flags & COLORFLAG_DARKER:
                brightness *= 0.66
            else:
                brightness = min(brightness * 1.2, 1.0)
            return make_bright_color(rgb, PALETTE_BRIGHTNESS), brightness
        if node["is_file"]:
            return PALETTE[indexes.get(extension_key(node["name"]), len(PALETTE) - 1)], OPTIONS["brightness"]
        return (0, 0, 0), OPTIONS["brightness"]

    def draw_cushion(rect, surface, color, brightness):
        left, top, right, bottom = rect
        scale = brightness / PALETTE_BRIGHTNESS
        col_r, col_g, col_b = (float(c) for c in color)
        for y in range(top, bottom):
            ny = -(2.0 * surface[1] * (y + 0.5) + surface[3])
            row = (y * width) * 3
            for x in range(left, right):
                nx = -(2.0 * surface[0] * (x + 0.5) + surface[2])
                cosa = (nx * lx + ny * ly + lz) / math.sqrt(nx * nx + ny * ny + 1.0)
                cosa = min(cosa, 1.0)
                pixel = max(shading * cosa, 0.0)
                pixel += ia
                pixel *= scale
                r, g, b = normalize_color(int(col_r * pixel), int(col_g * pixel), int(col_b * pixel))
                offset = row + x * 3
                pixels[offset] = r
                pixels[offset + 1] = g
                pixels[offset + 2] = b

    if root["size"] == 0:
        return pixels, leaves

    stack = [(root, (0, 0, width, height), [0.0, 0.0, 0.0, 0.0], OPTIONS["height"], True, 0)]
    while stack:
        node, rect, surface, h, is_root, depth = stack.pop()
        left, top, right, bottom = rect
        if right - left <= 0 or bottom - top <= 0:
            continue
        if not is_root:
            surface = add_ridge(rect, surface, h)
        if not node["children"]:
            color, brightness = leaf_color(node)
            draw_cushion(rect, surface, color, brightness)
            leaves.append({
                "path": node["path"],
                "ext": extension_key(node["name"]),
                "size": node["size"],
                "depth": depth,
                "rect": [left, top, right - left, bottom - top],
            })
            continue
        for child, child_rect in kdirstat_children(node, rect):
            stack.append((child, child_rect, surface, h * OPTIONS["scale_factor"], False, depth + 1))
    return pixels, leaves


def build_exporter(repo):
    subprocess.run(["make", "-C", str(repo / "Tools")], check=True, stdout=subprocess.DEVNULL)
    for candidate in (repo / "Tools/obj/windirstat-parity-exporter", repo / "Tools/windirstat-parity-exporter"):
        if candidate.exists():
            return candidate
    raise FileNotFoundError("could not find built windirstat-parity-exporter")


def exporter_environment():
    env = os.environ.copy()
    home = Path(os.environ.get("WINDIRSTAT_PARITY_HOME", "/tmp/lindirstat-gnustep-home"))
    defaults_dir = home / "GNUstep/Defaults"
    defaults_dir.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(home)
    env["GNUSTEP_USER_ROOT"] = str(home / "GNUstep")
    env["GNUSTEP_USER_DEFAULTS_DIR"] = str(defaults_dir)
    return env


def lindirstat_render(exporter, spec_path, fixture_name, width, height, ppm_path):
    completed = subprocess.run(
        [str(exporter), str(spec_path), fixture_name, str(width), str(height), "--ppm", str(ppm_path)],
        env=exporter_environment(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        completed.check_returncode()
    items = json.loads(completed.stdout)
    return read_ppm(ppm_path), items


def read_ppm(path):
    data = Path(path).read_bytes()
    parts = data.split(b"\n", 3)
    return bytearray(parts[3])


def write_ppm(path, pixels, width, height):
    with open(path, "wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        f.write(bytes(pixels))


def pixel_metrics(actual, expected, width, height):
    total = width * height
    exact = 0
    max_delta = 0
    squared = 0
    diff = bytearray(total * 3)
    for i in range(total):
        o = i * 3
        delta = max(abs(actual[o + k] - expected[o + k]) for k in range(3))
        if delta == 0:
            exact += 1
        else:
            diff[o] = 255
        max_delta = max(max_delta, delta)
        squared += sum((actual[o + k] - expected[o + k]) ** 2 for k in range(3))
    return {
        "exact_pixel_match": exact / total,
        "max_channel_delta": max_delta,
        "rmse": math.sqrt(squared / (total * 3)) / 255.0,
    }, diff


def rect_metrics(actual_items, expected_items):
    expected = {item["path"]: [int(v) for v in item["rect"]] for item in expected_items}
    actual = {item["path"]: [int(round(v)) for v in item["rect"]] for item in actual_items}
    mismatched = sorted(path for path in set(expected) | set(actual) if expected.get(path) != actual.get(path))
    return {
        "leaf_count": len(expected),
        "rect_mismatches": len(mismatched),
        "first_mismatches": mismatched[:5],
    }


def main():
    repo = Path(__file__).resolve().parents[1]
    spec_path = repo / "Tests/Fixtures/windirstat-parity/trees.json"
    out_dir = Path(os.environ.get("WINDIRSTAT_PARITY_OUT", repo / "dist/validation/windirstat-parity"))
    strict = os.environ.get("WINDIRSTAT_PARITY_STRICT", "1") != "0"
    out_dir.mkdir(parents=True, exist_ok=True)
    spec = json.loads(spec_path.read_text())
    exporter = build_exporter(repo)

    results = []
    for fixture in spec["fixtures"]:
        root = prepare(fixture["tree"])
        for width, height in spec["sizes"]:
            stem = f"{fixture['name']}-{width}x{height}"
            actual, actual_items = lindirstat_render(
                exporter, spec_path, fixture["name"], width, height, out_dir / f"{stem}-lindirstat.ppm")
            expected, expected_items = oracle_render(root, width, height)
            write_ppm(out_dir / f"{stem}-windirstat-oracle.ppm", expected, width, height)
            pixels, diff = pixel_metrics(actual, expected, width, height)
            write_ppm(out_dir / f"{stem}-diff.ppm", diff, width, height)
            (out_dir / f"{stem}-lindirstat-rects.json").write_text(json.dumps(actual_items, indent=2))
            (out_dir / f"{stem}-windirstat-oracle-rects.json").write_text(json.dumps(expected_items, indent=2))
            results.append({
                "fixture": fixture["name"],
                "size": [width, height],
                "geometry": rect_metrics(actual_items, expected_items),
                "image": pixels,
            })

    summary = {
        "strict": strict,
        "oracle": "Python port of references/WinDirStat/windirstat/Controls/TreeMap.cpp (KDirStat style, default options)",
        "thresholds": THRESHOLDS,
        "results": results,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    failures = []
    for result in results:
        name = f"{result['fixture']} {result['size'][0]}x{result['size'][1]}"
        print(f"{name:40} exact={result['image']['exact_pixel_match']:.4f} "
              f"maxΔ={result['image']['max_channel_delta']:3d} "
              f"rect mismatches={result['geometry']['rect_mismatches']}")
        if result["image"]["exact_pixel_match"] < THRESHOLDS["exact_pixel_match_min"]:
            failures.append(f"{name}: exact pixel match below threshold")
        if result["image"]["max_channel_delta"] > THRESHOLDS["max_channel_delta_max"]:
            failures.append(f"{name}: channel delta above threshold")
        if result["geometry"]["rect_mismatches"] > THRESHOLDS["rect_mismatch_max"]:
            failures.append(f"{name}: leaf rectangles differ ({result['geometry']['first_mismatches']})")

    print(f"WinDirStat parity outputs: {out_dir}")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1 if strict else 0
    print("PASS: production treemap matches the WinDirStat oracle")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
