#!/usr/bin/env python3
"""Full-window GUI parity gate on macOS (parity plan M11).

The macOS counterpart of scripts/gui-parity-gate.py, whose fixture, layout
checks and treemap checks it reuses. Run it with `make -C macos gui-gate`.

macOS has no private display to run on, so the gate works on the real
screen without taking it over:

* the app is driven only through its own accessibility elements
  (macos/gui-gate/macgate.swift): rows are selected, tabs pressed, the context
  menu shown and menu items chosen without moving the mouse or typing;
* screenshots are of LinDirStat's window alone (screencapture -l), scaled
  back to points on Retina displays;
* the app's defaults domain is backed up, emptied for each style and
  restored afterwards, and no other LinDirStat may be running;
* the style comes from LINDIRSTAT_APPEARANCE instead of the desktop's.

Checks that differ from the GNUstep gate: the menu bar is the system's (the
application menu, then WinDirStat's menus, then Window and Help), and the
title bar and toolbar are the system's in the requested appearance instead
of the Adwaita header bar. The treemap must still match the Phase 11
renderer pixel for pixel.

It needs Accessibility and Screen Recording permission for the terminal it
runs in. Output: dist/validation/gui-parity-macos.
"""
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUILD = REPO / "macos/build"
APP = BUILD / "LinDirStat.app/Contents/MacOS/LinDirStat"
EXPORTER = BUILD / "windirstat-parity-exporter"
MACGATE = BUILD / "macgate"
DOMAIN = "io.github.danjboyd.LinDirStat"

spec = importlib.util.spec_from_file_location("gui_parity_gate", REPO / "scripts/gui-parity-gate.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

# The macOS menu bar: the application menu first, Window and Help last.
MAC_MENU = ["LinDirStat"] + base.MAIN_MENU
MAC_MENU_TAIL = ["Window", "Help"]
MENU_CHECK = "main menu has WinDirStat's menus in order and is reachable"
OVERLAP_CHECKS = ("no overlapping sibling views", "no overlapping views in Settings")
# The system's window chrome overlaps the content by design (the title bar and
# toolbar over a full-size content view, Liquid Glass scroll pockets).
SYSTEM_CHROME = ("NSVisualEffectView", "NSTitlebar", "_NSTitlebar", "BackdropView", "_NSScrollViewContentBackgroundView",
                 "NSThemeFrame", "_NSThemeWidget", "NSToolbarView")

STYLES = {
    "light": {"appearance": "light", "defaults": {}, "columns": ["Physical Size", "Files", "Last Change"]},
    "dark": {"appearance": "dark", "defaults": {"ShowColumnSizeLogical": True},
             "columns": ["Physical Size", "Logical Size", "Files", "Last Change"]},
}


class MacGate(base.Gate):
    """Swaps the GNUstep-only checks for their macOS counterparts."""

    layout = None

    def check(self, style, state, name, ok, detail=None):
        if name == MENU_CHECK:
            menu = self.layout["mainMenu"] if self.layout else []
            ok = (menu[:1] == MAC_MENU[:1] and [t for t in menu if t in MAC_MENU] == MAC_MENU
                  and menu[-len(MAC_MENU_TAIL):] == MAC_MENU_TAIL)
            name, detail = "menu bar has the application menu, WinDirStat's menus in order, Window and Help", menu
        elif name in OVERLAP_CHECKS and detail:
            detail = [pair for pair in detail if not any(marker in pair for marker in SYSTEM_CHROME)]
            ok = not detail
        return super().check(style, state, name, ok, detail)


class OffsetImage(base.Image):
    """A window screenshot addressed in screen points."""

    def __init__(self, rgb, width, height, origin):
        super().__init__(rgb, width, height)
        self.origin = origin

    def pixel(self, x, y):
        return super().pixel(int(x) - self.origin[0], int(y) - self.origin[1])

    def crop(self, rect):
        x, y, w, h = rect
        return super().crop([int(x) - self.origin[0], int(y) - self.origin[1], w, h])


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, text=True, stdout=subprocess.PIPE, **kwargs).stdout


def macgate(*args, check=True):
    completed = subprocess.run([str(MACGATE), *[str(a) for a in args]], text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and completed.returncode != 0:
        raise RuntimeError(f"macgate {' '.join(map(str, args))}: {completed.stderr.strip()}")
    return completed.stdout.strip()


def running_lindirstat():
    completed = subprocess.run(["pgrep", "-x", "LinDirStat"], text=True, stdout=subprocess.PIPE)
    return {int(p) for p in completed.stdout.split()}


class Defaults:
    """The app's defaults domain, backed up and restored around the gate."""

    def __init__(self, backup):
        self.backup = backup
        exported = subprocess.run(["defaults", "export", DOMAIN, str(backup)], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
        self.existed = exported.returncode == 0

    def reset(self, values):
        subprocess.run(["defaults", "delete", DOMAIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for key, value in values.items():
            kind = "-bool" if isinstance(value, bool) else "-string"
            text = ("YES" if value else "NO") if isinstance(value, bool) else str(value)
            run("defaults", "write", DOMAIN, key, kind, text)

    def restore(self):
        subprocess.run(["defaults", "delete", DOMAIN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if self.existed:
            run("defaults", "import", DOMAIN, self.backup)

    def snapshot(self):
        completed = subprocess.run(["defaults", "export", DOMAIN, "-"], stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL)
        return completed.stdout if completed.returncode == 0 else b""


class App:
    def __init__(self, work, scan_path, appearance):
        work.mkdir(parents=True, exist_ok=True)
        self.dump_path = work / "layout.json"
        if self.dump_path.exists():
            self.dump_path.unlink()
        env = os.environ.copy()
        env.update({"LINDIRSTAT_DUMP_LAYOUT": str(self.dump_path), "LINDIRSTAT_SCAN_PATH": str(scan_path),
                    "LINDIRSTAT_APPEARANCE": appearance})
        self.log = open(work / "app.log", "w")
        # The checks read WinDirStat's English titles, whatever the Mac's language.
        self.process = subprocess.Popen([str(APP), "-AppleLanguages", "(en)"], env=env, cwd=str(work), stdout=self.log,
                                        stderr=subprocess.STDOUT)
        self.pid = self.process.pid
        self.work = work

    def stop(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.log.close()

    layout = base.App.layout
    wait_for = base.App.wait_for

    def capture(self, path):
        number, x, y, w, h = (int(v) for v in macgate("window", self.pid).split())
        run("screencapture", "-x", "-o", "-l", number, path)
        scale = max(1, round(int(run("sips", "-g", "pixelWidth", path).split()[-1]) / w))
        raw = path.with_suffix(".rgb")
        width, height = (int(v) for v in macgate("rgb", path, raw, scale).split())
        return OffsetImage(bytearray(raw.read_bytes()), width, height, (x, y))


# macOS 26 rounds windows with toolbars by about 40 points.
CORNER_RADIUS = 44


def mask_window_corners(image, layout, reference_pixels):
    """The window's rounded corners clip whatever content reaches them; those
    pixels take the reference's values. Returns how many were masked."""
    x, y, w, h = base.main_window(layout)["rect"]
    area = layout["treemap"]["area"]
    width = layout["treemap"]["renderSize"][0]
    masked = 0
    for cx, cy in ((x + CORNER_RADIUS, y + h - CORNER_RADIUS), (x + w - CORNER_RADIUS, y + h - CORNER_RADIUS),
                   (x + CORNER_RADIUS, y + CORNER_RADIUS), (x + w - CORNER_RADIUS, y + CORNER_RADIUS)):
        for py in range(cy - CORNER_RADIUS, cy + CORNER_RADIUS + 1):
            for px in range(cx - CORNER_RADIUS, cx + CORNER_RADIUS + 1):
                inside_area = area[0] <= px < area[0] + area[2] and area[1] <= py < area[1] + area[3]
                in_corner = ((px < x + CORNER_RADIUS or px >= x + w - CORNER_RADIUS)
                             and (py < y + CORNER_RADIUS or py >= y + h - CORNER_RADIUS))
                if inside_area and in_corner and (px - cx) ** 2 + (py - cy) ** 2 > (CORNER_RADIUS - 2) ** 2:
                    o = ((py - area[1]) * width + (px - area[0])) * 3
                    i = ((py - image.origin[1]) * image.width + (px - image.origin[0])) * 3
                    image.rgb[i:i + 3] = reference_pixels[o:o + 3]
                    masked += 1
    return masked


def context_menu(layout):
    """Items of the open context menu (the dump's openMenus), or None."""
    for menu in layout.get("openMenus", []):
        if not menu.get("mainMenu") and "Move to Trash" in menu["items"]:
            return menu["items"]
    return None


def check_chrome(gate, style_name, state, layout, image):
    window = base.main_window(layout)
    x, y, w, h = window["rect"]
    sample = image.crop([x, y, w, h])
    colors = {bytes(sample[i:i + 3]) for i in range(0, len(sample), 3 * 97)}
    gate.check(style_name, state, "screenshot not blank", len(colors) > 50, len(colors))
    # Bare title bar between the window buttons and the title.
    title_bar = image.mean([x + 84, y + 3, 16, 4])
    dark = style_name == "dark"
    ok = base.luminance(title_bar) <= 80 if dark else base.luminance(title_bar) >= 200
    gate.check(style_name, state, f"system title bar in the {style_name} appearance", ok,
               [round(c) for c in title_bar])


def run_style(gate, style_name, style, fixture_root, spec_json, parity, out_dir, defaults):
    style_dir = out_dir / style_name
    style_dir.mkdir(parents=True, exist_ok=True)
    work = out_dir / "work" / style_name
    references = {}

    def reference(width, height):
        if (width, height) not in references:
            pixels, items = base.exporter_render(parity, fixture_root, width, height, style_dir, work)
            oracle_root = parity.prepare(base.tree_spec_from_disk(fixture_root))
            oracle_pixels, oracle_items = parity.oracle_render(oracle_root, width, height)
            prefix = str(fixture_root.parent) + "/"
            exporter_items = [{**item, "path": item["path"][len(prefix):]} for item in items]
            oracle_rects = parity.rect_metrics(exporter_items, oracle_items)
            oracle_pixel_metrics, _ = parity.pixel_metrics(pixels, oracle_pixels, width, height)
            metrics = {**oracle_rects, "exact_pixel_match": round(oracle_pixel_metrics["exact_pixel_match"], 5),
                       "max_channel_delta": oracle_pixel_metrics["max_channel_delta"]}
            metrics["ok"] = (oracle_rects["rect_mismatches"] == 0
                             and oracle_pixel_metrics["exact_pixel_match"] >= base.TREEMAP_THRESHOLDS["exact_pixel_match_min"]
                             and oracle_pixel_metrics["max_channel_delta"] <= base.TREEMAP_THRESHOLDS["max_channel_delta_max"])
            references[(width, height)] = (pixels, items, metrics)
        return references[(width, height)]

    # A fixed window: 1280x820 content, as on GNUstep (AppKit adds the title
    # bar and toolbar to the saved frame). NSWindow frames are bottom-left based.
    defaults.reset({"ScanForDuplicates": True, **style["defaults"],
                    "NSWindow Frame LinDirStatMainWindow": "100 60 1280 820 0 0 1920 1080 "})
    states = {}
    app = App(work, fixture_root, style["appearance"])

    def capture(state, layout):
        shot = style_dir / f"{state}.png"
        image = app.capture(shot)
        (style_dir / f"{state}.json").write_text(json.dumps(layout, indent=1))
        states[state] = {"screenshot": str(shot.relative_to(REPO)), "layout": f"{style_name}/{state}.json"}
        gate.layout = layout
        return image

    def missing(state, what):
        gate.check(style_name, state, f"reached: {what}", False, "timed out")

    def layout_checks(state, layout):
        gate.layout = layout
        base.check_layout(gate, style_name, state, layout, style)

    try:
        # 1. Completed scan, duplicates found.
        layout = app.wait_for(lambda l: l["state"]["root"] == str(fixture_root) and not l["state"]["busy"]
                              and not l["state"]["findingDuplicates"] and l["treemap"]["leafCount"] > 0
                              and "duplicates" in [t["id"] for t in l["tabs"]["tabs"]], timeout=60, settle=1.0)
        if not layout:
            missing("scan-complete", "completed scan")
            return states
        macgate("activate", app.pid, check=False)
        time.sleep(0.5)
        layout = app.layout()
        image = capture("scan-complete", layout)
        layout_checks("scan-complete", layout)
        check_chrome(gate, style_name, "scan-complete", layout, image)
        base.check_list_background(gate, style_name, "scan-complete", layout, image)
        gate.check(style_name, "scan-complete", "file tabs in WinDirStat's order",
                   [t["label"] for t in layout["tabs"]["tabs"]] == base.FILE_TABS,
                   [t["label"] for t in layout["tabs"]["tabs"]])
        if layout["treemap"].get("scale", 1) != 1:
            # Screenshots are compared in points; a Retina treemap has more pixels.
            gate.note(style_name, "scan-complete", "treemap rendered above 1x; pixel and frame checks skipped",
                      layout["treemap"]["scale"])
            return states
        rendered = reference(*layout["treemap"]["renderSize"])[0]
        masked = mask_window_corners(image, layout, rendered)
        gate.note(style_name, "scan-complete", "treemap pixels under the window's rounded corners not compared", masked)
        base.check_treemap(gate, style_name, "scan-complete", layout, image, reference, parity, style_dir,
                           spec_json["expect"])

        # 2. An extension selected: its files are framed in the treemap.
        row = layout["tables"]["extensionTable"]["rows"][0]
        macgate("select", app.pid, *base.center(row["rect"]))
        layout = app.wait_for(lambda l: l["treemap"]["highlightedExtension"] != "")
        if layout:
            image = capture("extension-selected", layout)
            layout_checks("extension-selected", layout)
            key = layout["treemap"]["highlightedExtension"].lstrip(".").lower()
            highlighted = [leaf for leaf in layout["treemap"]["leaves"]
                           if parity.extension_key(Path(leaf["path"]).name) == key
                           and leaf["rect"][2] >= 3 and leaf["rect"][3] >= 3]
            framed = [base.frame_drawn(image, layout, leaf["rect"], rendered) for leaf in highlighted]
            gate.check(style_name, "extension-selected", "files of the selected extension are framed",
                       highlighted and min(framed) >= 0.9,
                       {"extension": key, "leaves": len(highlighted), "min_framed": framed and round(min(framed), 3)})
        else:
            missing("extension-selected", "extension highlighted in the treemap")

        # 3. A folder selected in the tree is framed in the treemap.
        rows = (layout or app.layout())["tables"]["directoryTable"]["rows"]
        target = rows[1]
        macgate("select", app.pid, *base.center(target["rect"]))
        layout = app.wait_for(lambda l: l["treemap"].get("selected", {}).get("path") == target["label"]
                              and l["treemap"]["highlightedExtension"] == "")
        if layout:
            image = capture("tree-selection", layout)
            layout_checks("tree-selection", layout)
            share = base.frame_drawn(image, layout, layout["treemap"]["selected"]["rect"], rendered)
            gate.check(style_name, "tree-selection", "tree selection framed in the treemap", share >= 0.9,
                       {"path": target["label"], "framed": round(share, 3)})
        else:
            missing("tree-selection", f"treemap selection of {target['label']}")

        # 4, 5. Largest Files and Duplicate Files tabs.
        for tab_id, state, role, minimum in (("largest", "largest-files", "largestTable", 10),
                                              ("duplicates", "duplicates", "duplicatesTable", 2)):
            tab = next(t for t in app.layout()["tabs"]["tabs"] if t["id"] == tab_id)
            macgate("press", app.pid, *base.center(tab["rect"]))
            layout = app.wait_for(lambda l: l["tabs"]["selected"] == tab_id and role in l["tables"]
                                  and l["tables"][role]["rowCount"] >= minimum)
            if not layout:
                missing(state, f"{tab['label']} tab with rows")
                continue
            capture(state, layout)
            layout_checks(state, layout)
            gate.check(style_name, state, f"{tab['label']} lists rows", True, layout["tables"][role]["rowCount"])

        # 6. The file tree's context menu.
        tab = next(t for t in app.layout()["tabs"]["tabs"] if t["id"] == "all")
        macgate("press", app.pid, *base.center(tab["rect"]))
        layout = app.wait_for(lambda l: l["tabs"]["selected"] == "all")
        if layout:
            # As VoiceOver's "show menu": the context menu of the selected row.
            row = layout["tables"]["directoryTable"]["rows"][1]
            macgate("menu", app.pid, *base.center(row["rect"]), check=False)
            layout = app.wait_for(lambda l: context_menu(l) is not None, timeout=10)
        if layout:
            capture("context-menu", layout)
            items = context_menu(layout)
            gate.check(style_name, "context-menu", "context menu has WinDirStat's commands in order",
                       [i for i in items if i in base.CONTEXT_MENU] == base.CONTEXT_MENU, items)
            gate.note(style_name, "context-menu", "context menu placement",
                      "macOS menus are not windows; AppKit keeps them on screen")
            macgate("escape", app.pid, check=False)
            closed = app.wait_for(lambda l: context_menu(l) is None, timeout=5)
            gate.check(style_name, "context-menu", "context menu closes with Escape", closed is not None)
        else:
            missing("context-menu", "context menu")

        # 7. Settings (WinDirStat's Options dialog).
        macgate("menuitem", app.pid, "LinDirStat", "Settings…")
        layout = app.wait_for(lambda l: any(w["title"] in ("Preferences", "Settings") for w in l["windows"]))
        if layout:
            capture("preferences", layout)
            window = next(w for w in layout["windows"] if w["title"] in ("Preferences", "Settings"))
            gate.check(style_name, "preferences", "Settings window fully on screen",
                       base.contains(layout["screen"], window["rect"]), window["rect"])
            overlaps = base.overlapping_siblings(window)
            gate.check(style_name, "preferences", "no overlapping views in Settings", not overlaps, overlaps[:5])
        else:
            missing("preferences", "Settings window")
    finally:
        app.stop()
    return states


def main():
    out_dir = Path(os.environ.get("GUI_PARITY_OUTPUT_DIR", REPO / "dist/validation/gui-parity-macos"))
    strict = os.environ.get("GUI_PARITY_STRICT", "1") != "0"
    styles = [s for s in os.environ.get("GUI_PARITY_STYLES", "light,dark").split(",") if s]
    out_dir.mkdir(parents=True, exist_ok=True)
    for needed in (APP, EXPORTER, MACGATE):
        if not needed.exists():
            print(f"missing {needed}; run make -C macos gui-gate", file=sys.stderr)
            return 2
    if running_lindirstat():
        print("quit LinDirStat first: it shares the defaults the gate resets", file=sys.stderr)
        return 2

    gate = MacGate(out_dir, strict)
    spec_json = json.loads(base.FIXTURE_SPEC.read_text())
    work = out_dir / "work"
    work.mkdir(exist_ok=True)
    fixture_root = base.generate_fixture(spec_json, work / "fixture").resolve()
    parity = base.load_parity_module()
    parity.build_exporter = lambda repo: EXPORTER
    defaults = Defaults(work / "defaults-backup.plist")
    before = defaults.snapshot()
    print(f"macOS GUI parity gate: {fixture_root}")
    results = {}
    try:
        for style_name in styles:
            print(f"[{style_name}]")
            results[style_name] = run_style(gate, style_name, STYLES[style_name], fixture_root, spec_json, parity,
                                            out_dir, defaults)
    finally:
        defaults.restore()
    gate.check("all", "teardown", "user defaults restored", defaults.snapshot() == before)

    failures = gate.failures()
    summary = {
        "platform": "macOS",
        "strict": strict,
        "fixture": str(base.FIXTURE_SPEC.relative_to(REPO)),
        "proportions": {"tree_pane": base.TREE_PANE_SHARE, "treemap": base.TREEMAP_SHARE,
                        "tolerance": base.SHARE_TOLERANCE},
        "treemap_thresholds": base.TREEMAP_THRESHOLDS,
        "styles": results,
        "findings": gate.findings,
        "checks": gate.checks,
        "failures": len(failures),
        "result": "PASS" if not failures else "FAIL",
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(f"GUI parity outputs: {out_dir}")
    if failures:
        for failure in failures:
            print(f"  FAIL {failure}", file=sys.stderr)
        print(f"FAIL: {len(failures)} of {len(gate.checks)} checks failed", file=sys.stderr)
        return 1 if strict else 0
    print(f"PASS: {len(gate.checks)} full-window checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
