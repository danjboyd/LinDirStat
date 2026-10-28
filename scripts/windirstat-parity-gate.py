#!/usr/bin/env python3
"""WinDirStat treemap parity gate.

Renders each fixture tree twice:

* LinDirStat: the production LDTreemap layout and cushion renderer, invoked
  through Tools/windirstat-parity-exporter.
* Oracle: an independent Python port of WinDirStat's CTreeMap and
  TreeMapLayout (references/WinDirStat/windirstat/Controls/TreeMap.cpp,
  TreeMap.h and TreeMapLayout.cpp, v2.9.3): the rows (KDirStat) and
  squarified (SequoiaView) layouts, cushion and flat shading, the grid,
  saturation and the colour presets, the equalized default palette and
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

# TreeMap.h DefaultOptions (v2.9.3).
OPTIONS = {
    "grid": False,
    "grid_color": (0, 0, 0),
    "brightness": 0.88,
    "saturation": 1.0,
    "height": 0.38,
    "scale_factor": 0.91,
    "ambient_light": 0.13,
    "light_x": -1.0,
    "light_y": -1.0,
}

# CTreeMap::GetGridColor's CLR_DEFAULT: COLOR_WINDOW blended 12% towards
# COLOR_WINDOWTEXT. The exporter renders with a white window and black text.
GRID_AUTO = "auto"
WINDOW_COLOR = (255, 255, 255)
WINDOW_TEXT_COLOR = (0, 0, 0)


def preset_options(name):
    """CTreeMap::GetPreset (TreeMap.cpp v2.9.3)."""
    options = dict(OPTIONS)
    if name == "classic":
        return options
    options.update(grid=True, grid_color=GRID_AUTO, brightness=0.72, saturation=0.65,
                   height=0.15, scale_factor=0.80, ambient_light=0.70)
    if name == "flat":
        options.update(saturation=0.85, height=0.0, ambient_light=1.0)
    elif name == "pastel":
        options.update(brightness=0.82, saturation=0.40, height=0.10, ambient_light=0.85)
    elif name == "high-contrast":
        options.update(grid_color=(0, 0, 0), brightness=0.62, saturation=1.0, height=0.0, ambient_light=1.0)
    return options


# Rendering variants beyond the default options: (name, preset, style). They
# run at the first viewport size only.
VARIANTS = [
    ("sequoia", "classic", "sequoia"),
    ("calm", "calm", "kdirstat"),
    ("flat", "flat", "kdirstat"),
    ("pastel", "pastel", "kdirstat"),
    ("high-contrast", "high-contrast", "kdirstat"),
]
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


# Port of references/WinDirStat/windirstat/Controls/TreeMapLayout.cpp
# (v2.9.3): children get integer weights; rows and squarified strips are
# cut with C++'s truncating double-to-int conversions.

def arrange_equal_rows(bounds, weights):
    left, top, right, bottom = bounds
    width = (right - left) / len(weights)
    out = []
    x = float(left)
    for i in range(len(weights)):
        nxt = x + width
        r = right if i + 1 == len(weights) else int(nxt)
        out.append((int(x), top, r, bottom))
        x = nxt
    return out


def arrange_rows(bounds, parent_weight, weights):
    """TreeMapLayout ArrangeRows (KDirStat style)."""
    if parent_weight == 0:
        return arrange_equal_rows(bounds, weights)
    left, top, right, bottom = bounds
    bw, bh = right - left, bottom - top
    horizontal = bw >= bh
    normalized_width = bw / bh if horizontal else bh / bw
    row_origin = top if horizontal else left
    row_extent = bh if horizontal else bw
    column_extent = bw if horizontal else bh
    regions = [None] * len(weights)
    f_top = float(row_origin)
    row_begin = 0
    while row_begin < len(weights):
        row_weight = 0
        row_fraction = 0.0
        row_end = row_begin
        while row_end < len(weights):
            child_weight = weights[row_end]
            if child_weight == 0:
                break
            row_weight += child_weight
            candidate = row_weight / parent_weight
            child_width = child_weight / parent_weight * normalized_width / candidate
            if child_width / candidate < MIN_PROPORTION:
                row_weight -= child_weight
                break
            row_fraction = candidate
            row_end += 1
        if row_end == row_begin:
            break
        while row_end < len(weights) and weights[row_end] == 0:
            row_end += 1
        next_top = f_top + row_fraction * row_extent
        row_bottom = (bottom if horizontal else right) if row_end == len(weights) else int(next_top)
        f_left = float(left if horizontal else top)
        for i in range(row_begin, row_end):
            if weights[i] == 0:
                continue
            next_left = f_left + weights[i] / row_weight * column_extent
            last = i + 1 == row_end or (i + 1 < len(weights) and weights[i + 1] == 0)
            r = (right if horizontal else bottom) if last else int(next_left)
            if horizontal:
                regions[i] = (int(f_left), int(f_top), r, row_bottom)
            else:
                regions[i] = (int(f_top), int(f_left), row_bottom, r)
            f_left = next_left
        f_top = next_top
        row_begin = row_end
    return regions


def arrange_squarified(bounds, parent_weight, weights):
    """TreeMapLayout ArrangeSquarified (SequoiaView style)."""
    if parent_weight == 0:
        return arrange_equal_rows(bounds, weights)
    left, top, right, bottom = bounds
    remaining = [left, top, right, bottom]
    remaining_weight = parent_weight
    weight_per_pixel = remaining_weight / (right - left) / (bottom - top)
    regions = [None] * len(weights)
    head = 0
    while head < len(weights) and remaining[2] > remaining[0] and remaining[3] > remaining[1]:
        rw, rh = remaining[2] - remaining[0], remaining[3] - remaining[1]
        horizontal = rw >= rh
        thickness = rh if horizontal else rw
        squared_row_weight = thickness * thickness * weight_per_pixel
        row_begin = head
        row_end = head
        worst = float("inf")
        largest = weights[row_begin]
        row_weight = 0
        while row_end < len(weights):
            child_weight = weights[row_end]
            if child_weight == 0:
                row_end = len(weights)
                break
            next_weight = float(row_weight) + child_weight
            squared = next_weight * next_weight
            next_worst = max(squared_row_weight * largest / squared, squared / squared_row_weight / child_weight)
            if next_worst > worst:
                break
            row_weight += child_weight
            row_end += 1
            worst = next_worst
        if row_weight == 0:
            break
        extent = rw if horizontal else rh
        row_width = min(max(int(row_weight / remaining_weight * extent), 1), extent) if row_weight < remaining_weight else extent
        row = list(remaining)
        if horizontal:
            row[2] = row[0] + row_width
        else:
            row[3] = row[1] + row_width
        begin = float(row[1] if horizontal else row[0])
        for i in range(row_begin, row_end):
            if weights[i] == 0:
                continue
            nxt = begin + weights[i] / row_weight * ((row[3] - row[1]) if horizontal else (row[2] - row[0]))
            last = i + 1 == row_end or (i + 1 < len(weights) and weights[i + 1] == 0)
            end = (row[3] if horizontal else row[2]) if last else int(nxt)
            if horizontal:
                regions[i] = (row[0], int(begin), row[2], end)
            else:
                regions[i] = (int(begin), row[1], end, row[3])
            begin = nxt
        if horizontal:
            remaining[0] += row_width
        else:
            remaining[1] += row_width
        remaining_weight -= row_weight
        head += row_end - row_begin
    return regions


def arrange_children(node, rect, style):
    """TreeMapLayout::ArrangeChildren: children sorted by weight, empty regions skipped."""
    children = node["children"]
    weights = [c["size"] for c in children]
    if not weights or rect[2] <= rect[0] or rect[3] <= rect[1]:
        return []
    arrange = arrange_squarified if style == "sequoia" else arrange_rows
    regions = arrange(rect, node["size"], weights)
    return [(child, region) for child, region in zip(children, regions)
            if region is not None and region[2] > region[0] and region[3] > region[1]]


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


def blend(color, background, amount):
    """CColorSpace::BlendColor."""
    return tuple(int(c * (1.0 - amount) + b * amount) for c, b in zip(color, background))


def oracle_render(root, width, height, options=OPTIONS, style="kdirstat"):
    """Port of CTreeMap::DrawTreeMap: layout, grid, flat or cushion leaves."""
    grid_color = options["grid_color"]
    if grid_color == GRID_AUTO:
        grid_color = blend(WINDOW_COLOR, WINDOW_TEXT_COLOR, 0.12)
    # LinDirStat fills the background with the grid colour with or without
    # the grid (the default black), which only shows in the grid's gaps.
    pixels = bytearray(bytes(grid_color) * (width * height))
    leaves = []
    indexes = color_indexes(root)
    cushions = options["ambient_light"] < 1.0 and options["height"] > 0.0 and options["scale_factor"] > 0.0

    lx, ly, lz = options["light_x"], options["light_y"], 10.0
    length = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / length, ly / length, lz / length
    ia = options["ambient_light"]
    shading = 1.0 - ia

    def desaturate(color):
        """PrepareRenderColor's saturation step: blend towards the integer grey."""
        gray = sum(color) // 3
        return blend(color, (gray, gray, gray), 1.0 - min(max(options["saturation"], 0.0), 1.0))

    def leaf_color(node):
        """PrepareRenderColor: flagged colors are equalized and drawn darker or lighter, then desaturated."""
        brightness = options["brightness"]
        if node["space"] is not None:
            rgb, flags = SPACE_COLORS[node["space"]]
            if flags & COLORFLAG_DARKER:
                brightness *= 0.66
            else:
                brightness = min(brightness * 1.2, 1.0)
            return desaturate(make_bright_color(rgb, PALETTE_BRIGHTNESS)), brightness
        if node["is_file"]:
            return desaturate(PALETTE[indexes.get(extension_key(node["name"]), len(PALETTE) - 1)]), brightness
        return desaturate((0, 0, 0)), brightness

    def draw_solid(rect, color, brightness):
        """DrawSolidRect: the palette colour scaled by brightness, normalized."""
        left, top, right, bottom = rect
        scale = brightness / PALETTE_BRIGHTNESS
        rgb = bytes(normalize_color(int(color[0] * scale), int(color[1] * scale), int(color[2] * scale)))
        for y in range(top, bottom):
            row = (y * width + left) * 3
            pixels[row:row + (right - left) * 3] = rgb * (right - left)

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

    grid_width = 1 if options["grid"] else 0
    stack = [(root, (0, 0, width, height), [0.0, 0.0, 0.0, 0.0], options["height"], True, 0)]
    while stack:
        node, rect, surface, h, is_root, depth = stack.pop()
        left, top, right, bottom = rect
        if right - left <= grid_width or bottom - top <= grid_width:
            continue
        if cushions and not is_root:
            surface = add_ridge(rect, surface, h)
        if not node["children"]:
            color, brightness = leaf_color(node)
            # RenderLeaf: with the grid, the top and left pixel are the grid.
            drawn = (left + grid_width, top + grid_width, right, bottom)
            if cushions:
                draw_cushion(drawn, surface, color, brightness)
            else:
                draw_solid(drawn, color, brightness)
            leaves.append({
                "path": node["path"],
                "ext": extension_key(node["name"]),
                "size": node["size"],
                "depth": depth,
                "rect": [left, top, right - left, bottom - top],
            })
            continue
        for child, child_rect in arrange_children(node, rect, style):
            stack.append((child, child_rect, surface, h * options["scale_factor"], False, depth + 1))
    return pixels, leaves


def build_exporter(repo):
    # A prebuilt exporter (the macOS build: make -C macos exporter).
    prebuilt = os.environ.get("WINDIRSTAT_PARITY_EXPORTER")
    if prebuilt:
        return Path(prebuilt)
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


def lindirstat_render(exporter, spec_path, fixture_name, width, height, ppm_path, extra=()):
    completed = subprocess.run(
        [str(exporter), *extra, str(spec_path), fixture_name, str(width), str(height), "--ppm", str(ppm_path)],
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

    runs = [("default", None, "kdirstat", size) for size in spec["sizes"]]
    runs += [(name, preset, style, spec["sizes"][0]) for name, preset, style in VARIANTS]
    results = []
    for fixture in spec["fixtures"]:
        root = prepare(fixture["tree"])
        for variant, preset, style, (width, height) in runs:
            stem = f"{fixture['name']}-{width}x{height}" + ("" if variant == "default" else f"-{variant}")
            extra = [] if preset is None else ["--preset", preset, "--style", style]
            options = OPTIONS if preset is None else preset_options(preset)
            actual, actual_items = lindirstat_render(
                exporter, spec_path, fixture["name"], width, height, out_dir / f"{stem}-lindirstat.ppm", extra)
            expected, expected_items = oracle_render(root, width, height, options, style)
            write_ppm(out_dir / f"{stem}-windirstat-oracle.ppm", expected, width, height)
            pixels, diff = pixel_metrics(actual, expected, width, height)
            write_ppm(out_dir / f"{stem}-diff.ppm", diff, width, height)
            (out_dir / f"{stem}-lindirstat-rects.json").write_text(json.dumps(actual_items, indent=2))
            (out_dir / f"{stem}-windirstat-oracle-rects.json").write_text(json.dumps(expected_items, indent=2))
            results.append({
                "fixture": fixture["name"],
                "variant": variant,
                "size": [width, height],
                "geometry": rect_metrics(actual_items, expected_items),
                "image": pixels,
            })

    summary = {
        "strict": strict,
        "oracle": "Python port of references/WinDirStat/windirstat/Controls/TreeMap.cpp and TreeMapLayout.cpp "
                  "(v2.9.3: rows and squarified layouts, default options and the colour presets)",
        "thresholds": THRESHOLDS,
        "results": results,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    failures = []
    for result in results:
        name = f"{result['fixture']} {result['size'][0]}x{result['size'][1]} {result['variant']}"
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
