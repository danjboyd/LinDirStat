#!/usr/bin/env python3
import json
import math
import os
import subprocess
import sys
from pathlib import Path


WIN_PALETTE = [
    (0, 0, 255), (255, 0, 0), (0, 255, 0), (255, 255, 0),
    (0, 255, 255), (255, 0, 255), (255, 170, 0), (0, 85, 255),
    (255, 0, 85), (85, 255, 0), (170, 0, 255), (0, 255, 85),
    (255, 0, 170), (0, 170, 255), (255, 85, 0), (0, 255, 170),
    (85, 0, 255), (255, 255, 255),
]

LD_PALETTE = [
    (33, 120, 201), (222, 77, 56), (46, 158, 89), (240, 176, 51),
    (140, 89, 179), (0, 148, 148), (191, 79, 140), (107, 107, 107),
]


def stable_hash(text):
    value = 5381
    for ch in text:
        value = ((value << 5) + value) + ord(ch)
    return value


def extension(name):
    if "." not in name:
        return "<none>"
    ext = name.rsplit(".", 1)[1].lower()
    return ext or "<none>"


def prepare(node, path=""):
    node = dict(node)
    node["path"] = f"{path}/{node['name']}" if path else node["name"]
    children = [prepare(child, node["path"]) for child in node.get("children", [])]
    node["children"] = children
    if children:
        node["size"] = sum(child["aggregate_size"] for child in children)
    node["aggregate_size"] = int(node.get("size", 0))
    return node


def children_by_size(node):
    return sorted(node.get("children", []), key=lambda c: (-c["aggregate_size"], c["name"]))


def leaves(node):
    if not node.get("children"):
        return [node]
    out = []
    for child in children_by_size(node):
        out.extend(leaves(child))
    return out


def kdir_arrange(node, width, height):
    children = children_by_size(node)
    if not children or width <= 0 or height <= 0:
        return True, [], [], []
    horizontal_rows = width >= height
    row_width = width if horizontal_rows else height
    row_height = height if horizontal_rows else width
    total = node["aggregate_size"] or 1
    rows = []
    children_per_row = []
    child_widths = []
    row_start = 0
    while row_start < len(children):
        row_sum = 0
        row_count = 0
        best = float("inf")
        while row_start + row_count < len(children):
            child = children[row_start + row_count]
            size = child["aggregate_size"]
            if size <= 0:
                row_count += 1
                child_widths.append(0.0)
                continue
            trial_sum = row_sum + size
            row_fraction = max(trial_sum / total, 1e-12)
            row_pixels = max(row_fraction * row_height, 1e-12)
            worst = 0.0
            for i in range(row_start, row_start + row_count + 1):
                s = children[i]["aggregate_size"]
                if s <= 0:
                    continue
                child_fraction = (s / total) / row_fraction
                child_pixels = max(child_fraction * row_width, 1e-12)
                ratio = max(child_pixels / row_pixels, row_pixels / child_pixels)
                worst = max(worst, ratio)
            if row_count > 0 and worst > best:
                break
            best = worst
            row_sum = trial_sum
            row_count += 1
        if row_count == 0:
            row_count = 1
            row_sum = children[row_start]["aggregate_size"]
        row_fraction = row_sum / total
        rows.append(row_fraction)
        children_per_row.append(row_count)
        for i in range(row_start, row_start + row_count):
            size = children[i]["aggregate_size"]
            child_widths.append(0.0 if row_sum <= 0 else size / row_sum)
        row_start += row_count
    return horizontal_rows, rows, children_per_row, child_widths


def oracle_layout(node, rect, depth=0):
    x, y, w, h = rect
    if node["aggregate_size"] <= 0 or w <= 0 or h <= 0:
        return []
    children = children_by_size(node)
    if not children:
        return [{
            "path": node["path"],
            "name": node["name"],
            "ext": extension(node["name"]),
            "size": node["aggregate_size"],
            "depth": depth,
            "rect": [x, y, w, h],
        }]
    horizontal, rows, counts, child_widths = kdir_arrange(node, w, h)
    out = []
    top = y if horizontal else x
    c = 0
    for row_index, row_fraction in enumerate(rows):
        bottom = top + row_fraction * (h if horizontal else w)
        if row_index == len(rows) - 1:
            bottom = y + h if horizontal else x + w
        left = x if horizontal else y
        for i in range(counts[row_index]):
            child = children[c]
            right = left + child_widths[c] * (w if horizontal else h)
            if i == counts[row_index] - 1:
                right = x + w if horizontal else y + h
            if horizontal:
                child_rect = [left, top, right - left, bottom - top]
            else:
                child_rect = [top, left, bottom - top, right - left]
            out.extend(oracle_layout(child, child_rect, depth + 1))
            left = right
            c += 1
    return out


def normalize_palette_color(rgb, brightness=0.6):
    total = sum(rgb)
    if total == 0:
        return rgb
    factor = 3.0 * brightness * 255.0 / total
    values = [int(v * factor) for v in rgb]
    while max(values) > 255:
        i = values.index(max(values))
        extra = values[i] - 255
        values[i] = 255
        values[(i + 1) % 3] += extra // 2
        values[(i + 2) % 3] += extra - extra // 2
    return tuple(max(0, min(255, v)) for v in values)


def color_for_ext(ext, oracle):
    palette = [normalize_palette_color(c) for c in WIN_PALETTE] if oracle else LD_PALETTE
    return palette[stable_hash(ext) % len(palette)]


def build_exporter(repo):
    subprocess.run(["make", "-C", str(repo / "Tools")], check=True)
    candidates = [
        repo / "Tools/obj/windirstat-parity-exporter",
        repo / "Tools/windirstat-parity-exporter",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("could not find built windirstat-parity-exporter")


def lindirstat_layout_from_exporter(exporter, spec_path, fixture_name, width, height):
    env = os.environ.copy()
    exporter_home = Path(os.environ.get("WINDIRSTAT_PARITY_HOME", "/tmp/lindirstat-gnustep-home"))
    defaults_dir = exporter_home / "GNUstep/Defaults"
    defaults_dir.mkdir(parents=True, exist_ok=True)
    env["HOME"] = str(exporter_home)
    env["GNUSTEP_USER_ROOT"] = str(exporter_home / "GNUstep")
    env["GNUSTEP_USER_DEFAULTS_DIR"] = str(defaults_dir)
    completed = subprocess.run(
        [str(exporter), str(spec_path), fixture_name, str(width), str(height)],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        completed.check_returncode()
    return json.loads(completed.stdout)


def render(items, width, height, oracle=False):
    pixels = [(0, 0, 0)] * (width * height)
    for item in items:
        x, y, w, h = item["rect"]
        x0 = max(0, int(math.floor(x)) + 1)
        y0 = max(0, int(math.floor(y)) + 1)
        x1 = min(width, int(math.ceil(x + w)) - 1)
        y1 = min(height, int(math.ceil(y + h)) - 1)
        base = color_for_ext(item["ext"], oracle)
        for py in range(y0, y1):
            for px in range(x0, x1):
                if oracle:
                    nx = (px - x0) / max(1, x1 - x0)
                    ny = (py - y0) / max(1, y1 - y0)
                    shade = 0.62 + 0.30 * (1.0 - (nx + ny) / 2.0)
                    color = tuple(max(0, min(255, int(c * shade))) for c in base)
                else:
                    color = base
                pixels[py * width + px] = color
    return pixels


def raster_coverage_metrics(items, width, height):
    counts = [0] * (width * height)
    for item in items:
        x, y, w, h = item["rect"]
        x0 = max(0, int(math.floor(x)))
        y0 = max(0, int(math.floor(y)))
        x1 = min(width, int(math.ceil(x + w)))
        y1 = min(height, int(math.ceil(y + h)))
        for py in range(y0, y1):
            row = py * width
            for px in range(x0, x1):
                counts[row + px] += 1
    total = width * height
    covered = sum(1 for count in counts if count > 0)
    gaps = sum(1 for count in counts if count == 0)
    overlaps = sum(1 for count in counts if count > 1)
    return {
        "covered_pixel_ratio": covered / total,
        "gap_pixel_ratio": gaps / total,
        "overlap_pixel_ratio": overlaps / total,
    }


def area_proportionality_metrics(items, total_size, width, height):
    total_pixels = width * height
    errors = []
    weighted_errors = []
    for item in items:
        if item["size"] <= 0 or total_size <= 0:
            continue
        expected = item["size"] / total_size
        _, _, w, h = item["rect"]
        actual = max(0.0, w) * max(0.0, h) / total_pixels
        error = abs(actual - expected)
        errors.append(error)
        weighted_errors.append(error * expected)
    return {
        "max_area_share_error": max(errors) if errors else 0.0,
        "mean_area_share_error": sum(errors) / max(1, len(errors)),
        "weighted_area_share_error": sum(weighted_errors),
    }


def luminance(pixel):
    return 0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]


def edge_density(pixels, width, height):
    edges = 0
    comparisons = 0
    threshold = 35.0
    for y in range(height):
        for x in range(width):
            here = luminance(pixels[y * width + x])
            if x + 1 < width:
                comparisons += 1
                if abs(here - luminance(pixels[y * width + x + 1])) >= threshold:
                    edges += 1
            if y + 1 < height:
                comparisons += 1
                if abs(here - luminance(pixels[(y + 1) * width + x])) >= threshold:
                    edges += 1
    return edges / max(1, comparisons)


def color_histogram(pixels, bucket_size=32):
    histogram = {}
    for r, g, b in pixels:
        key = (r // bucket_size, g // bucket_size, b // bucket_size)
        histogram[key] = histogram.get(key, 0) + 1
    total = len(pixels)
    return {key: value / total for key, value in histogram.items()}


def histogram_intersection(left, right):
    keys = set(left) | set(right)
    return sum(min(left.get(key, 0.0), right.get(key, 0.0)) for key in keys)


def write_ppm(path, pixels, width, height):
    with open(path, "wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        f.write(bytes(channel for pixel in pixels for channel in pixel))


def image_metrics(actual, expected):
    if len(actual) != len(expected):
        raise ValueError("image sizes differ")
    n = len(actual)
    mse = sum(sum((a[i] - e[i]) ** 2 for i in range(3)) for a, e in zip(actual, expected)) / (n * 3)
    rmse = math.sqrt(mse) / 255.0
    exact = sum(1 for a, e in zip(actual, expected) if a == e) / n
    return {
        "rmse": rmse,
        "exact_pixel_match": exact,
        "similarity": max(0.0, 1.0 - rmse),
    }


def image_parity_metrics(actual, expected, width, height):
    base = image_metrics(actual, expected)
    actual_edge_density = edge_density(actual, width, height)
    expected_edge_density = edge_density(expected, width, height)
    base.update({
        "edge_density_actual": actual_edge_density,
        "edge_density_expected": expected_edge_density,
        "edge_density_delta": abs(actual_edge_density - expected_edge_density),
        "color_histogram_intersection": histogram_intersection(color_histogram(actual), color_histogram(expected)),
    })
    return base


def geometry_metrics(actual, expected, root_size, width, height):
    by_path = {item["path"]: item for item in expected}
    aspect_delta = []
    center_delta = []
    matched_paths = 0
    for item in actual:
        other = by_path.get(item["path"])
        if not other:
            continue
        matched_paths += 1
        ax, ay, aw, ah = item["rect"]
        ex, ey, ew, eh = other["rect"]
        a_aspect = max(aw / max(ah, 1e-9), ah / max(aw, 1e-9))
        e_aspect = max(ew / max(eh, 1e-9), eh / max(ew, 1e-9))
        aspect_delta.append(abs(math.log(a_aspect) - math.log(e_aspect)))
        center_delta.append(math.hypot((ax + aw / 2) - (ex + ew / 2), (ay + ah / 2) - (ey + eh / 2)))
    total_area = sum(max(0.0, item["rect"][2]) * max(0.0, item["rect"][3]) for item in actual)
    metrics = {
        "area_coverage": total_area / (width * height),
        "matched_path_ratio": matched_paths / max(1, len(expected)),
        "mean_aspect_log_delta": sum(aspect_delta) / max(1, len(aspect_delta)),
        "mean_center_delta_px": sum(center_delta) / max(1, len(center_delta)),
    }
    metrics.update(raster_coverage_metrics(actual, width, height))
    metrics.update(area_proportionality_metrics(actual, root_size, width, height))
    return metrics


def main():
    repo = Path(__file__).resolve().parents[1]
    spec_path = repo / "Tests/Fixtures/windirstat-parity/trees.json"
    out_dir = Path(os.environ.get("WINDIRSTAT_PARITY_OUT", repo / "dist/validation/windirstat-parity"))
    strict = os.environ.get("WINDIRSTAT_PARITY_STRICT") == "1"
    out_dir.mkdir(parents=True, exist_ok=True)
    spec = json.loads(spec_path.read_text())
    exporter = build_exporter(repo)
    results = []
    oracle_metadata = {
        "reference": "references/WinDirStat/windirstat/Controls/TreeMap.h and TreeMap.cpp",
        "style": "KDirStatStyle",
        "palette": "DefaultCushionColors normalized to palette brightness 0.6",
        "rendering": "cushion-like top-left light gradient used as a portable test approximation",
        "grid": "one-pixel dark separators in raster output",
        "limitations": [
            "The oracle is a deterministic parity model, not a compiled WinDirStat binary.",
            "Cushion shading is approximated for stable cross-platform comparison.",
            "Strict thresholds should be calibrated after the production renderer implements matching squarification and shading."
        ]
    }
    (out_dir / "windirstat-oracle-metadata.json").write_text(json.dumps(oracle_metadata, indent=2))
    for fixture in spec["fixtures"]:
        root = prepare(fixture["tree"])
        for width, height in spec["sizes"]:
            actual_items = lindirstat_layout_from_exporter(exporter, spec_path, fixture["name"], width, height)
            expected_items = oracle_layout(root, [0.0, 0.0, float(width), float(height)])
            actual = render(actual_items, width, height, oracle=False)
            expected = render(expected_items, width, height, oracle=True)
            stem = f"{fixture['name']}-{width}x{height}"
            write_ppm(out_dir / f"{stem}-lindirstat.ppm", actual, width, height)
            write_ppm(out_dir / f"{stem}-windirstat-oracle.ppm", expected, width, height)
            result = {
                "fixture": fixture["name"],
                "size": [width, height],
                "leaf_count": len(leaves(root)),
                "geometry": geometry_metrics(actual_items, expected_items, root["aggregate_size"], width, height),
                "image": image_parity_metrics(actual, expected, width, height),
            }
            (out_dir / f"{stem}-lindirstat-rects.json").write_text(json.dumps(actual_items, indent=2))
            (out_dir / f"{stem}-windirstat-oracle-rects.json").write_text(json.dumps(expected_items, indent=2))
            results.append(result)
    summary = {
        "strict": strict,
        "lin_dir_stat_renderer": str(exporter),
        "oracle_metadata": "windirstat-oracle-metadata.json",
        "results": results,
        "thresholds": {
            "strict_similarity_min": 0.82,
            "strict_aspect_log_delta_max": 0.45,
            "coverage_min": 0.98,
            "gap_pixel_ratio_max": 0.02,
            "overlap_pixel_ratio_max": 0.03,
            "weighted_area_share_error_max": 0.01,
            "color_histogram_intersection_min": 0.35,
            "edge_density_delta_max": 0.08,
        },
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    min_similarity = min(r["image"]["similarity"] for r in results)
    max_aspect_delta = max(r["geometry"]["mean_aspect_log_delta"] for r in results)
    min_coverage = min(r["geometry"]["area_coverage"] for r in results)
    max_gap_ratio = max(r["geometry"]["gap_pixel_ratio"] for r in results)
    max_overlap_ratio = max(r["geometry"]["overlap_pixel_ratio"] for r in results)
    max_area_error = max(r["geometry"]["weighted_area_share_error"] for r in results)
    min_histogram = min(r["image"]["color_histogram_intersection"] for r in results)
    max_edge_delta = max(r["image"]["edge_density_delta"] for r in results)
    print(f"WinDirStat parity outputs: {out_dir}")
    print(f"min image similarity: {min_similarity:.3f}")
    print(f"max mean aspect delta: {max_aspect_delta:.3f}")
    print(f"min area coverage: {min_coverage:.3f}")
    print(f"max gap pixel ratio: {max_gap_ratio:.3f}")
    print(f"max overlap pixel ratio: {max_overlap_ratio:.3f}")
    print(f"max weighted area error: {max_area_error:.3f}")
    print(f"min color histogram intersection: {min_histogram:.3f}")
    print(f"max edge density delta: {max_edge_delta:.3f}")
    if min_coverage < 0.98 or max_gap_ratio > 0.02 or max_overlap_ratio > 0.03 or max_area_error > 0.01:
        print("FAIL: treemap does not sufficiently cover the render area", file=sys.stderr)
        return 1
    if strict and (
        min_similarity < 0.82
        or max_aspect_delta > 0.45
        or min_histogram < 0.35
        or max_edge_delta > 0.08
    ):
        print("FAIL: strict WinDirStat visual parity thresholds were not met", file=sys.stderr)
        return 1
    if not strict:
        print("Non-strict mode records visual parity metrics without failing known treemap gaps.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
