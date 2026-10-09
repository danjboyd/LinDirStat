#!/usr/bin/env python3
"""Full-window GUI parity gate (roadmap 12J, parity plan L11).

Runs the built app on a private Xvfb display with private GNUstep defaults,
scans a fixture tree generated from Tests/Fixtures/gui-parity/tree.json, drives
it through the states WinDirStat users see (completed scan, extension
selected, tree selection framed in the treemap, Largest Files, Duplicate
Files, the context menu, Preferences) in the light and dark styles, and checks
every state:

* from the geometry the app reports (LINDIRSTAT_DUMP_LAYOUT): WinDirStat's
  pane composition and proportions, columns present and in order, toolbar,
  menu and status bar present, no overlapping sibling views, no clipped column
  titles, treemap density;
* from screenshots: not blank, the Adwaita theme and the requested style
  applied, and the treemap pixels and leaf rectangles identical to the Phase
  11 renderer (Tools/windirstat-parity-exporter) for the same tree, which the
  WinDirStat oracle of scripts/windirstat-parity-gate.py checks in turn.

Strict by default: any failed check fails the gate. GUI_PARITY_STRICT=0
records the results without failing. Output: dist/validation/gui-parity.

Never touches the user's display or defaults: the app runs with GNUSTEP_HOME
in the output folder, and the gate fails if ~/GNUstep/Defaults changes.
"""
import hashlib
import importlib.util
import json
import math
import os
import plistlib
import pwd
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
APP = REPO / "Source/LinDirStat.app/LinDirStat"
FIXTURE_SPEC = REPO / "Tests/Fixtures/gui-parity/tree.json"
SCREEN = (1600, 1000)

# WinDirStat's composition (MainFrame.cpp: RestoreSplitterPos(0.72) for the
# file view, 0.5 for the treemap). LinDirStat gives the file view 60% so the
# extension list's description fits at GNOME's metrics
# (AppController -applyDefaultSplitPositions).
TREE_PANE_SHARE = 0.60
TREEMAP_SHARE = 0.50
SHARE_TOLERANCE = 0.02

MAIN_MENU = ["File", "Edit", "Clean Up", "Treemap", "Options"]
TOOLBAR = ["SelectTarget", "Refresh", "Suspend", "Stop", "NSToolbarFlexibleSpaceItem",
           "Search", "Trash", "SelectParent", "ZoomOut", "ZoomIn"]
# Item.h / FileTreeView.cpp: fixed columns, then the optional ones in order.
TREE_FIXED = ["Name", "Subtree Percentage", "Percentage"]
TREE_OPTIONAL = ["Physical Size", "Logical Size", "Items", "Files", "Folders", "Last Change", "Attributes", "Owner"]
EXTENSION_COLUMNS = ["Extension", "Color", "Description", "Bytes", "% Bytes", "Files"]
LARGEST_COLUMNS = ["Name", "Physical Size", "Logical Size", "Last Change"]
DUPLICATE_COLUMNS = ["Hash Prefix / Name", "Items", "Physical Size", "Logical Size", "Last Change"]
FILE_TABS = ["All Files", "Largest Files", "Duplicate Files"]
CONTEXT_MENU = ["Open", "Copy Path", "Refresh Selected", "Properties", "Move to Trash",
                "Delete Permanently…", "Empty Folder…", "Move To…", "Custom Cleanup", "Open With"]

# Light: the app's own column defaults. Dark: WinDirStat's defaults (Logical
# Size on, which LinDirStat leaves off on Linux).
STYLES = {
    "light": {"color_scheme": "default", "defaults": {},
              "columns": ["Physical Size", "Files", "Last Change"]},
    "dark": {"color_scheme": "prefer-dark", "defaults": {"ShowColumnSizeLogical": True},
             "columns": ["Physical Size", "Logical Size", "Files", "Last Change"]},
}

TREEMAP_THRESHOLDS = {"exact_pixel_match_min": 0.999, "max_channel_delta_max": 2, "rect_mismatch_max": 0}


class Gate:
    def __init__(self, out_dir, strict):
        self.out = out_dir
        self.strict = strict
        self.checks = []
        self.findings = []

    def check(self, style, state, name, ok, detail=None):
        self.checks.append({"style": style, "state": state, "check": name, "pass": bool(ok), "detail": detail})
        mark = "ok  " if ok else "FAIL"
        print(f"  {mark} {state:18} {name}" + ("" if ok or detail is None else f": {detail}"))
        return ok

    def note(self, style, state, name, detail):
        """A finding to report that the gate does not fail on."""
        finding = {"style": style, "state": state, "finding": name, "detail": detail}
        if not any(f["finding"] == name and f["style"] == style for f in self.findings):
            self.findings.append(finding)
            print(f"  note {state:18} {name}: {detail}")

    def failures(self):
        return [c for c in self.checks if not c["pass"]]


# ---------------------------------------------------------------- fixture

def file_bytes(seed, size):
    """Deterministic contents; equal seeds give equal bytes."""
    block = b"".join(hashlib.sha256(f"{seed}:{i}".encode()).digest() for i in range(128))
    return (block * (size // len(block) + 1))[:size]


def generate_fixture(spec, parent):
    root = parent / spec["tree"]["name"]
    if root.exists():
        shutil.rmtree(root)
    mtime = spec["mtime"]

    def build(node, path):
        if "children" in node:
            path.mkdir(parents=True)
            for child in node["children"]:
                build(child, path / child["name"])
        else:
            seed = node.get("duplicate") or str(path.relative_to(parent))
            path.write_bytes(file_bytes(seed, node["size"]))
        os.utime(path, (mtime, mtime))

    build(spec["tree"], root)
    os.utime(root, (mtime, mtime))
    return root


def tree_spec_from_disk(path):
    """The tree as the scanner sees it (physical sizes) for the oracle."""
    if path.is_dir() and not path.is_symlink():
        return {"name": path.name, "children": [tree_spec_from_disk(child) for child in sorted(path.iterdir())]}
    return {"name": path.name, "size": path.lstat().st_blocks * 512}


# ---------------------------------------------------------------- isolation

def real_defaults_dir():
    return Path(pwd.getpwuid(os.getuid()).pw_dir) / "GNUstep/Defaults"


def defaults_snapshot():
    folder = real_defaults_dir()
    if not folder.is_dir():
        return {}
    return {str(p): p.stat().st_mtime_ns for p in folder.glob("*.plist")}


def other_lindirstat_processes():
    """LinDirStat instances the gate did not start (they write the user's defaults)."""
    found = set()
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                if os.readlink(entry / "exe").endswith("/LinDirStat"):
                    found.add(int(entry.name))
            except OSError:
                pass
    return found


GLOBAL_DEFAULTS = {
    # The checks read English titles, whatever the machine's language.
    "NSLanguages": ["English"],
    "GSTheme": "Adwaita",
    "GSX11HandlesWindowDecorations": "NO",
    "GSWindowDecoration": "Default",
    "NSMenuInterfaceStyle": "NSWindows95InterfaceStyle",
    "GnomeThemeMenuStyle": "primary",
    "GnomeThemeNativeFileDialogs": "NO",
    "GSSuppressAppIcon": 1,
    "GSShowToolTips": False,
    "GSScaleFactor": "1.0",
    "GSFirstCommandKey": "Control_L",
    "GSSecondCommandKey": "Control_R",
    "GSFirstControlKey": "Alt_L",
    "GSSecondControlKey": "Alt_R",
    "GSFirstAlternateKey": "Super_L",
    "GSSecondAlternateKey": "Super_R",
}


def prepare_home(style_dir, style):
    home = style_dir / "gshome"
    if home.exists():
        shutil.rmtree(home)
    defaults = home / "GNUstep/Defaults"
    defaults.mkdir(parents=True)
    # Themes and bundles are read from the user's library; nothing is written there.
    library = Path(pwd.getpwuid(os.getuid()).pw_dir) / "GNUstep/Library"
    if library.is_dir():
        (home / "GNUstep/Library").symlink_to(library)
    with open(defaults / "NSGlobalDomain.plist", "wb") as f:
        plistlib.dump(GLOBAL_DEFAULTS, f)
    app_defaults = {
        # A fixed window: 1280x820 content under the Adwaita header bar.
        "NSWindow Frame LinDirStatMainWindow": "99 99 1282 867 0 0  1600 1000 ",
        "ScanForDuplicates": True,
    }
    app_defaults.update(style["defaults"])
    with open(defaults / "LinDirStat.plist", "wb") as f:
        plistlib.dump(app_defaults, f)
    config = style_dir / "config/glib-2.0/settings"
    config.mkdir(parents=True, exist_ok=True)
    (config / "keyfile").write_text(f"[org/gnome/desktop/interface]\ncolor-scheme='{style['color_scheme']}'\n")
    return home


# ---------------------------------------------------------------- X server

def free_display():
    requested = os.environ.get("GUI_PARITY_DISPLAY")
    candidates = [int(requested.lstrip(":"))] if requested else range(90, 200)
    for number in candidates:
        if not Path(f"/tmp/.X11-unix/X{number}").exists() and not Path(f"/tmp/.X{number}-lock").exists():
            return f":{number}"
    raise RuntimeError(f"display {requested} is in use" if requested else "no free X display")


def start_xvfb(display):
    process = subprocess.Popen(["Xvfb", display, "-screen", "0", f"{SCREEN[0]}x{SCREEN[1]}x24", "-nolisten", "tcp"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    socket = Path(f"/tmp/.X11-unix/X{display.lstrip(':')}")
    for _ in range(100):
        if socket.exists():
            return process
        time.sleep(0.05)
    process.kill()
    raise RuntimeError("Xvfb did not start")


class App:
    def __init__(self, display, home, style_dir, scan_path):
        self.display = display
        self.dump_path = style_dir / "layout.json"
        if self.dump_path.exists():
            self.dump_path.unlink()
        env = os.environ.copy()
        env.update({
            "GNUSTEP_HOME": str(home),
            "HOME": str(home),
            "DISPLAY": display,
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent",
            "XDG_DATA_HOME": str(style_dir / "data"),
            "XDG_CONFIG_HOME": str(style_dir / "config"),
            "XDG_CACHE_HOME": str(style_dir / "cache"),
            "GSETTINGS_BACKEND": "keyfile",
            "LINDIRSTAT_DUMP_LAYOUT": str(self.dump_path),
            "LINDIRSTAT_SCAN_PATH": str(scan_path),
        })
        env.pop("LINDIRSTAT_APPEARANCE", None)
        self.log = open(style_dir / "app.log", "w")
        self.process = subprocess.Popen([str(APP)], env=env, cwd=str(style_dir),
                                        stdout=self.log, stderr=subprocess.STDOUT)

    def stop(self):
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.log.close()

    def layout(self):
        try:
            return json.loads(self.dump_path.read_text())
        except (OSError, ValueError):
            return None

    def wait_for(self, predicate, timeout=30.0, settle=0.6):
        """The first layout satisfying predicate, after the UI settles."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError("the app exited")
            layout = self.layout()
            if layout and predicate(layout):
                time.sleep(settle)
                layout = self.layout()
                if layout and predicate(layout):
                    return layout
            time.sleep(0.1)
        return None

    def xdotool(self, *args):
        subprocess.run(["xdotool", *args], env={**os.environ, "DISPLAY": self.display}, check=True)

    def click(self, point, button=1):
        x, y = (int(v) for v in point)
        self.xdotool("mousemove", str(x), str(y))
        time.sleep(0.15)
        self.xdotool("mousedown", str(button))
        time.sleep(0.1)
        self.xdotool("mouseup", str(button))

    def key(self, combo):
        self.xdotool("key", combo)

    def capture(self, path):
        subprocess.run(["import", "-window", "root", str(path)], env={**os.environ, "DISPLAY": self.display},
                       check=True)
        rgb = subprocess.run(["convert", str(path), "-depth", "8", "rgb:-"], check=True,
                             stdout=subprocess.PIPE).stdout
        return Image(rgb, SCREEN[0], SCREEN[1])


class Image:
    def __init__(self, rgb, width, height):
        self.rgb = rgb
        self.width = width
        self.height = height

    def pixel(self, x, y):
        o = (y * self.width + x) * 3
        return tuple(self.rgb[o:o + 3])

    def crop(self, rect):
        x, y, w, h = (int(v) for v in rect)
        rows = [self.rgb[((y + r) * self.width + x) * 3:((y + r) * self.width + x + w) * 3] for r in range(h)]
        return bytearray(b"".join(rows))

    def mean(self, rect):
        data = self.crop(rect)
        n = len(data) // 3
        return tuple(sum(data[k::3]) / n for k in range(3))


def center(rect):
    x, y, w, h = rect
    return (x + w / 2, y + h / 2)


def luminance(rgb):
    r, g, b = rgb
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


# ---------------------------------------------------------------- layout model

def walk(view, parent=None):
    yield view, parent
    for child in view.get("children", []):
        yield from walk(child, view)


def main_window(layout):
    for window in layout["windows"]:
        if "toolbar" in window:
            return window
    return None


def views_by_role(window):
    return {view["role"]: view for view, _ in walk(window["views"]) if "role" in view}


def menu_items(window):
    """Titles of the menu a window shows (GNUstep menus are NSMenuViews in panels)."""
    for view, _ in walk(window["views"]):
        if "menuItems" in view and view["rect"][3] > 0:
            return view["menuItems"]
    return []


def context_menu(layout):
    return next((w for w in layout["windows"] if "toolbar" not in w and "Move to Trash" in menu_items(w)), None)


def intersects(a, b):
    return min(a[0] + a[2], b[0] + b[2]) > max(a[0], b[0]) and min(a[1] + a[3], b[1] + b[3]) > max(a[1], b[1])


def contains(outer, inner):
    return (inner[0] >= outer[0] and inner[1] >= outer[1]
            and inner[0] + inner[2] <= outer[0] + outer[2] and inner[1] + inner[3] <= outer[1] + outer[3])


def overlapping_siblings(window):
    """Sibling views that overlap. Scroll views overlay their scrollers on
    purpose, so their parts are not compared."""
    found = []
    for view, _ in walk(window["views"]):
        if view["class"] in ("NSScrollView", "NSClipView"):
            continue
        children = [c for c in view.get("children", []) if len(c["rect"]) == 4 and c["rect"][2] > 0 and c["rect"][3] > 0]
        for i, a in enumerate(children):
            for b in children[i + 1:]:
                if intersects(a["rect"], b["rect"]):
                    found.append(f"{a['class']}{'/' + a['role'] if 'role' in a else ''} {a['rect']} x "
                                 f"{b['class']}{'/' + b['role'] if 'role' in b else ''} {b['rect']}")
    return found


def clipped_titles(layout):
    clipped = []
    for role, table in layout["tables"].items():
        for column in table["columns"]:
            if column["titleWidth"] > column["titleAreaWidth"]:
                clipped.append(f"{role}.{column['title']} ({column['titleWidth']} > {column['titleAreaWidth']})")
    return clipped


def hidden_titles(layout, role):
    """Column titles not fully visible in the pane without scrolling sideways."""
    table = layout["tables"][role]
    right = table["rect"][0] + table["rect"][2]
    hidden = []
    for column in table["columns"]:
        x, _, width, _ = column["rect"]
        inset = (width - column["titleAreaWidth"]) / 2
        if column["alignment"] == "right":
            end = x + width - inset
        elif column["alignment"] == "center":
            end = x + (width + column["titleWidth"]) / 2
        else:
            end = x + inset + column["titleWidth"]
        if end > right:
            hidden.append(column["title"])
    return hidden


def columns_past_pane(layout, role):
    table = layout["tables"][role]
    right = table["rect"][0] + table["rect"][2]
    return {c["title"]: c["rect"][0] + c["rect"][2] - right for c in table["columns"] if c["rect"][0] + c["rect"][2] > right}


def titles(layout, role):
    return [c["title"] for c in layout["tables"][role]["columns"]]


# ---------------------------------------------------------------- checks

def check_layout(gate, style_name, state, layout, style):
    window = main_window(layout)
    if not gate.check(style_name, state, "main window present", window is not None):
        return
    roles = views_by_role(window)
    content = window["content"]
    gate.check(style_name, state, "fixed window size 1280x820", content[2:] == [1280, 820], content)

    # Chrome: toolbar, menu, status bar.
    toolbar = window.get("toolbar", {})
    gate.check(style_name, state, "toolbar visible with WinDirStat's commands",
               toolbar.get("visible") and [i["id"] for i in toolbar.get("items", [])] == TOOLBAR,
               [i["id"] for i in toolbar.get("items", [])])
    menu = layout["mainMenu"]
    in_order = [title for title in menu if title in MAIN_MENU] == MAIN_MENU
    menu_access = [v["class"] for v, _ in walk(window["views"])
                   if (v["class"] == "NSMenuView" and v["rect"][3] > 0) or v["class"].endswith("MenuButton")]
    gate.check(style_name, state, "main menu has WinDirStat's menus in order and is reachable",
               in_order and menu_access, {"menu": menu, "access": menu_access})
    status = roles.get("statusField")
    status_ok = (status is not None and status.get("text") and contains(content, status["rect"])
                 and content[1] + content[3] - (status["rect"][1] + status["rect"][3]) <= 12)
    gate.check(style_name, state, "status bar at the bottom with text", status_ok, status and status["rect"])

    # WinDirStat's composition: file view left, extension list right, treemap below.
    panes = {name: roles.get(name) for name in ("mainSplit", "topSplit", "fileTabs", "extensionPane", "treemap")}
    missing = [name for name, view in panes.items() if view is None]
    if gate.check(style_name, state, "panes present", not missing, missing):
        top, main = panes["topSplit"]["rect"], panes["mainSplit"]["rect"]
        files, extensions, treemap = panes["fileTabs"]["rect"], panes["extensionPane"]["rect"], panes["treemap"]["rect"]
        tree_share = files[2] / top[2]
        treemap_share = treemap[3] / main[3]
        gate.check(style_name, state, f"file view takes {TREE_PANE_SHARE:.0%} of the width",
                   abs(tree_share - TREE_PANE_SHARE) <= SHARE_TOLERANCE, round(tree_share, 3))
        gate.check(style_name, state, f"treemap takes {TREEMAP_SHARE:.0%} of the height",
                   abs(treemap_share - TREEMAP_SHARE) <= SHARE_TOLERANCE, round(treemap_share, 3))
        gate.check(style_name, state, "extension list right of the file view, treemap full width below",
                   extensions[0] >= files[0] + files[2] and treemap[1] >= top[1] + top[3] and treemap[2] == main[2],
                   {"files": files, "extensions": extensions, "treemap": treemap})
        outside = [name for name, view in panes.items() if not contains(content, view["rect"])]
        gate.check(style_name, state, "panes inside the window content", not outside, outside)

    overlaps = overlapping_siblings(window)
    gate.check(style_name, state, "no overlapping sibling views", not overlaps, overlaps[:5])
    subpixel = sorted({v["role"] for v, _ in walk(window["views"]) if v.get("subpixel") and "role" in v})
    if subpixel:
        gate.note(style_name, state, "views off the pixel grid (fractional frames)", subpixel)
    clipped = clipped_titles(layout)
    gate.check(style_name, state, "no clipped column titles", not clipped, clipped)

    expected_tree = TREE_FIXED + [c for c in TREE_OPTIONAL if c in style["columns"]]
    if "directoryTable" in layout["tables"]:
        gate.check(style_name, state, "file tree columns in WinDirStat's order",
                   titles(layout, "directoryTable") == expected_tree, titles(layout, "directoryTable"))
        hidden = hidden_titles(layout, "directoryTable")
        gate.check(style_name, state, "file tree column titles visible without scrolling", not hidden, hidden)
        past = columns_past_pane(layout, "directoryTable")
        if past:
            gate.note(style_name, state, "file tree columns run past the pane (horizontal scrolling)",
                      {"pixels past the edge": past, "columns": titles(layout, "directoryTable")})
    if "extensionTable" in layout["tables"]:
        gate.check(style_name, state, "extension list columns in WinDirStat's order",
                   titles(layout, "extensionTable") == EXTENSION_COLUMNS, titles(layout, "extensionTable"))
        hidden = hidden_titles(layout, "extensionTable")
        gate.check(style_name, state, "extension list column titles visible without scrolling", not hidden, hidden)
        past = columns_past_pane(layout, "extensionTable")
        if past:
            gate.note(style_name, state, "extension list columns run past the pane (horizontal scrolling)",
                      {"pixels past the edge": past, "columns": titles(layout, "extensionTable")})
    for role, expected in (("largestTable", LARGEST_COLUMNS), ("duplicatesTable", DUPLICATE_COLUMNS)):
        if role in layout["tables"]:
            gate.check(style_name, state, f"{role} columns in WinDirStat's order",
                       titles(layout, role) == expected, titles(layout, role))


def check_image(gate, style_name, state, layout, image):
    window = main_window(layout)
    x, y, w, h = window["rect"]
    sample = image.crop([x, y, w, h])
    colors = {bytes(sample[i:i + 3]) for i in range(0, len(sample), 3 * 97)}
    gate.check(style_name, state, "screenshot not blank", len(colors) > 50, len(colors))

    decoration = window["views"]["class"]
    toolbar = next((v for v, _ in walk(window["views"]) if v["class"] == "GSToolbarView"), None)
    header = None
    if toolbar:
        tx, ty, tw, th = toolbar["rect"]
        buttons = [v["rect"] for v, _ in walk(toolbar) if v["class"] == "GSToolbarButton" and v.get("text")]
        # A patch of bare header bar just below the toolbar's top edge, right of the last left-hand button.
        left = max((r[0] + r[2] for r in buttons if r[0] < tx + tw / 2), default=tx)
        header = image.mean([left + 8, ty + 2, 16, 6])
    dark = style_name == "dark"
    themed = decoration.startswith("GnomeTheme") and header is not None
    style_ok = themed and (luminance(header) <= 80 if dark else luminance(header) >= 225)
    gate.check(style_name, state, f"Adwaita header bar in the {style_name} style", style_ok,
               {"decoration": decoration, "header": header and [round(c) for c in header]})


def check_list_background(gate, style_name, state, layout, image):
    table = layout["tables"].get("directoryTable")
    if not table:
        return
    x, y, w, h = table["rect"]
    rows = table["rows"]
    below = (rows[-1]["rect"][1] + rows[-1]["rect"][3]) if rows else y + 30
    if y + h - below < 20:
        return
    background = image.mean([x + 4, below + 4, 40, 10])
    dark = style_name == "dark"
    gate.check(style_name, state, f"list background in the {style_name} style",
               luminance(background) <= 80 if dark else luminance(background) >= 225,
               [round(c) for c in background])


def load_parity_module():
    spec = importlib.util.spec_from_file_location("windirstat_parity_gate", REPO / "scripts/windirstat-parity-gate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def exporter_render(parity, root, width, height, out_dir, home):
    exporter = parity.build_exporter(REPO)
    ppm = out_dir / f"treemap-exporter-{width}x{height}.ppm"
    env = {**os.environ, "GNUSTEP_HOME": str(home), "HOME": str(home), "LINDIRSTAT_TREEMAP_HEIGHT": str(height)}
    completed = subprocess.run([str(exporter), "--path", str(root), str(width), "--ppm", str(ppm)], env=env,
                               check=True, text=True, stdout=subprocess.PIPE)
    items = json.loads(completed.stdout)
    return parity.read_ppm(ppm), items


def relative_leaves(layout):
    area = layout["treemap"]["area"]
    return [{"path": leaf["path"], "rect": [leaf["rect"][0] - area[0], leaf["rect"][1] - area[1],
                                            leaf["rect"][2], leaf["rect"][3]]}
            for leaf in layout["treemap"]["leaves"]]


def check_treemap(gate, style_name, state, layout, image, reference, parity, out_dir, expect):
    treemap = layout["treemap"]
    width, height = treemap["renderSize"]
    expected_pixels, expected_items, oracle_metrics = reference(width, height)
    leaves = relative_leaves(layout)
    count = treemap["leafCount"]
    gate.check(style_name, state, "treemap density within the fixture's range",
               expect["leafCountMin"] <= count <= expect["leafCountMax"] and count == len(expected_items),
               {"leaves": count, "exporter": len(expected_items), "range": [expect["leafCountMin"], expect["leafCountMax"]]})
    rects = parity.rect_metrics(leaves, expected_items)
    gate.check(style_name, state, "treemap leaf rectangles match the Phase 11 renderer",
               rects["rect_mismatches"] <= TREEMAP_THRESHOLDS["rect_mismatch_max"], rects)
    actual = image.crop(treemap["area"])
    pixels, diff = parity.pixel_metrics(actual, expected_pixels, width, height)
    parity.write_ppm(out_dir / f"{state}-treemap-screen.ppm", actual, width, height)
    parity.write_ppm(out_dir / f"{state}-treemap-diff.ppm", diff, width, height)
    gate.check(style_name, state, "treemap pixels match the Phase 11 renderer",
               pixels["exact_pixel_match"] >= TREEMAP_THRESHOLDS["exact_pixel_match_min"]
               and pixels["max_channel_delta"] <= TREEMAP_THRESHOLDS["max_channel_delta_max"],
               {k: round(v, 5) if isinstance(v, float) else v for k, v in pixels.items()})
    gate.check(style_name, state, "Phase 11 renderer matches the WinDirStat oracle for the fixture",
               oracle_metrics["ok"], oracle_metrics)


def frame_drawn(image, layout, rect, rendered):
    """Share of a leaf rectangle's border pixels that differ from the plain
    rendering: WinDirStat frames selections and highlights on top."""
    area = layout["treemap"]["area"]
    width = layout["treemap"]["renderSize"][0]
    x, y, w, h = rect
    border = [(x + i, y) for i in range(w)] + [(x + i, y + h - 1) for i in range(w)]
    border += [(x, y + j) for j in range(h)] + [(x + w - 1, y + j) for j in range(h)]
    changed = 0
    for px, py in border:
        o = ((py - area[1]) * width + (px - area[0])) * 3
        if image.pixel(px, py) != tuple(rendered[o:o + 3]):
            changed += 1
    return changed / max(1, len(border))


# ---------------------------------------------------------------- states

def run_style(gate, style_name, style, display, fixture_root, spec, parity, out_dir):
    style_dir = out_dir / style_name
    style_dir.mkdir(parents=True, exist_ok=True)
    home = prepare_home(out_dir / "work" / style_name, style)
    references = {}

    def reference(width, height):
        if (width, height) not in references:
            pixels, items = exporter_render(parity, fixture_root, width, height, style_dir, home)
            oracle_root = parity.prepare(tree_spec_from_disk(fixture_root))
            oracle_pixels, oracle_items = parity.oracle_render(oracle_root, width, height)
            # The exporter names leaves by absolute path, the oracle relative to the root's parent.
            prefix = str(fixture_root.parent) + "/"
            exporter_items = [{**item, "path": item["path"][len(prefix):]} for item in items]
            oracle_rects = parity.rect_metrics(exporter_items, oracle_items)
            oracle_pixels_metrics, _ = parity.pixel_metrics(pixels, oracle_pixels, width, height)
            metrics = {**oracle_rects, "exact_pixel_match": round(oracle_pixels_metrics["exact_pixel_match"], 5),
                       "max_channel_delta": oracle_pixels_metrics["max_channel_delta"]}
            metrics["ok"] = (oracle_rects["rect_mismatches"] == 0
                             and oracle_pixels_metrics["exact_pixel_match"] >= TREEMAP_THRESHOLDS["exact_pixel_match_min"]
                             and oracle_pixels_metrics["max_channel_delta"] <= TREEMAP_THRESHOLDS["max_channel_delta_max"])
            references[(width, height)] = (pixels, items, metrics)
        return references[(width, height)]

    states = {}
    app = App(display, home, out_dir / "work" / style_name, fixture_root)

    def capture(state, layout):
        shot = style_dir / f"{state}.png"
        image = app.capture(shot)
        (style_dir / f"{state}.json").write_text(json.dumps(layout, indent=1))
        states[state] = {"screenshot": str(shot.relative_to(REPO)) if shot.is_relative_to(REPO) else str(shot),
                         "layout": f"{style_name}/{state}.json"}
        return image

    def missing(state, what):
        gate.check(style_name, state, f"reached: {what}", False, "timed out")

    try:
        # 1. Completed scan, duplicates found.
        layout = app.wait_for(lambda l: l["state"]["root"] == str(fixture_root) and not l["state"]["busy"]
                              and not l["state"]["findingDuplicates"] and l["treemap"]["leafCount"] > 0
                              and "duplicates" in [t["id"] for t in l["tabs"]["tabs"]], timeout=60, settle=1.0)
        if not layout:
            missing("scan-complete", "completed scan")
            return states
        image = capture("scan-complete", layout)
        check_layout(gate, style_name, "scan-complete", layout, style)
        check_image(gate, style_name, "scan-complete", layout, image)
        check_list_background(gate, style_name, "scan-complete", layout, image)
        gate.check(style_name, "scan-complete", "file tabs in WinDirStat's order",
                   [t["label"] for t in layout["tabs"]["tabs"]] == FILE_TABS, [t["label"] for t in layout["tabs"]["tabs"]])
        check_treemap(gate, style_name, "scan-complete", layout, image, reference, parity, style_dir, spec["expect"])
        rendered = reference(*layout["treemap"]["renderSize"])[0]

        # 2. An extension selected: its files are highlighted in the treemap.
        row = layout["tables"]["extensionTable"]["rows"][0]
        app.click(center(row["rect"]))
        layout = app.wait_for(lambda l: l["treemap"]["highlightedExtension"] != "")
        if layout:
            image = capture("extension-selected", layout)
            check_layout(gate, style_name, "extension-selected", layout, style)
            key = layout["treemap"]["highlightedExtension"].lstrip(".").lower()
            highlighted = [leaf for leaf in layout["treemap"]["leaves"]
                           if parity.extension_key(Path(leaf["path"]).name) == key
                           and leaf["rect"][2] >= 3 and leaf["rect"][3] >= 3]
            framed = [frame_drawn(image, layout, leaf["rect"], rendered) for leaf in highlighted]
            gate.check(style_name, "extension-selected", "files of the selected extension are framed",
                       highlighted and min(framed) >= 0.9,
                       {"extension": key, "leaves": len(highlighted), "min_framed": framed and round(min(framed), 3)})
        else:
            missing("extension-selected", "extension highlighted in the treemap")

        # 3. A folder selected in the tree is framed in the treemap.
        rows = (layout or app.layout())["tables"]["directoryTable"]["rows"]
        target = rows[1]
        app.click(center(target["rect"]))
        layout = app.wait_for(lambda l: l["treemap"].get("selected", {}).get("path") == target["label"]
                              and l["treemap"]["highlightedExtension"] == "")
        if layout:
            image = capture("tree-selection", layout)
            check_layout(gate, style_name, "tree-selection", layout, style)
            share = frame_drawn(image, layout, layout["treemap"]["selected"]["rect"], rendered)
            gate.check(style_name, "tree-selection", "tree selection framed in the treemap", share >= 0.9,
                       {"path": target["label"], "framed": round(share, 3)})
        else:
            missing("tree-selection", f"treemap selection of {target['label']}")

        # 4, 5. Largest Files and Duplicate Files tabs.
        for tab_id, state, role, minimum in (("largest", "largest-files", "largestTable", 10),
                                              ("duplicates", "duplicates", "duplicatesTable", 2)):
            current = app.layout()
            tab = next(t for t in current["tabs"]["tabs"] if t["id"] == tab_id)
            app.click(center(tab["rect"]))
            layout = app.wait_for(lambda l: l["tabs"]["selected"] == tab_id and role in l["tables"]
                                  and l["tables"][role]["rowCount"] >= minimum)
            if not layout:
                missing(state, f"{tab['label']} tab with rows")
                continue
            capture(state, layout)
            check_layout(gate, style_name, state, layout, style)
            gate.check(style_name, state, f"{tab['label']} lists rows", True, layout["tables"][role]["rowCount"])

        # 6. The file tree's context menu.
        current = app.layout()
        tab = next(t for t in current["tabs"]["tabs"] if t["id"] == "all")
        app.click(center(tab["rect"]))
        layout = app.wait_for(lambda l: l["tabs"]["selected"] == "all")
        if layout:
            row = layout["tables"]["directoryTable"]["rows"][1]
            app.click(center(row["rect"]), button=3)
            layout = app.wait_for(lambda l: context_menu(l) is not None)
        if layout:
            image = capture("context-menu", layout)
            menu = context_menu(layout)
            items = [i for i in menu_items(menu) if i in CONTEXT_MENU]
            gate.check(style_name, "context-menu", "context menu has WinDirStat's commands in order",
                       items == CONTEXT_MENU, menu_items(menu))
            gate.check(style_name, "context-menu", "context menu fully on screen",
                       contains([0, 0, SCREEN[0], SCREEN[1]], menu["rect"]), menu["rect"])
            overlaps = overlapping_siblings(menu)
            gate.check(style_name, "context-menu", "no overlapping views in the menu", not overlaps, overlaps[:5])
            app.key("Escape")
            closed = app.wait_for(lambda l: context_menu(l) is None, timeout=3)
            if not closed:
                app.click(center(views_by_role(main_window(layout))["statusField"]["rect"]))
                app.wait_for(lambda l: context_menu(l) is None, timeout=5)
        else:
            missing("context-menu", "context menu")

        # 7. Preferences.
        app.key("ctrl+comma")
        layout = app.wait_for(lambda l: any(w["title"] in ("Preferences", "Settings") for w in l["windows"]))
        if layout:
            capture("preferences", layout)
            window = next(w for w in layout["windows"] if w["title"] in ("Preferences", "Settings"))
            gate.check(style_name, "preferences", "Preferences window fully on screen",
                       contains([0, 0, SCREEN[0], SCREEN[1]], window["rect"]), window["rect"])
            overlaps = overlapping_siblings(window)
            gate.check(style_name, "preferences", "no overlapping views in Preferences", not overlaps, overlaps[:5])
        else:
            missing("preferences", "Preferences window")
    finally:
        app.stop()
    return states


def main():
    out_dir = Path(os.environ.get("GUI_PARITY_OUTPUT_DIR", REPO / "dist/validation/gui-parity"))
    strict = os.environ.get("GUI_PARITY_STRICT", "1") != "0"
    styles = [s for s in os.environ.get("GUI_PARITY_STYLES", "light,dark").split(",") if s]
    out_dir.mkdir(parents=True, exist_ok=True)
    if not APP.exists():
        print(f"missing {APP}; build first", file=sys.stderr)
        return 2
    for tool in ("Xvfb", "xdotool", "import", "convert"):
        if not shutil.which(tool):
            print(f"missing {tool}", file=sys.stderr)
            return 2

    gate = Gate(out_dir, strict)
    spec = json.loads(FIXTURE_SPEC.read_text())
    work = out_dir / "work"
    work.mkdir(exist_ok=True)
    fixture_root = generate_fixture(spec, work / "fixture")
    parity = load_parity_module()
    before = defaults_snapshot()
    foreign = other_lindirstat_processes()
    display = free_display()
    xvfb = start_xvfb(display)
    print(f"GUI parity gate on {display}: {fixture_root}")
    results = {}
    try:
        for style_name in styles:
            print(f"[{style_name}]")
            results[style_name] = run_style(gate, style_name, STYLES[style_name], display, fixture_root, spec, parity,
                                            out_dir)
    finally:
        xvfb.terminate()
        xvfb.wait()
    after = defaults_snapshot()
    changed = sorted({path for path, _ in set(before.items()) ^ set(after.items())})
    others = foreign | other_lindirstat_processes()
    if changed and others:
        # Another LinDirStat (the user's own) saves into those defaults itself.
        gate.note("all", "teardown", "user defaults changed while other LinDirStat processes ran",
                  {"files": changed, "pids": sorted(others)})
    else:
        gate.check("all", "teardown", "user defaults untouched", not changed, changed)

    failures = gate.failures()
    summary = {
        "strict": strict,
        "display": display,
        "fixture": str(FIXTURE_SPEC.relative_to(REPO)),
        "proportions": {"tree_pane": TREE_PANE_SHARE, "treemap": TREEMAP_SHARE, "tolerance": SHARE_TOLERANCE},
        "treemap_thresholds": TREEMAP_THRESHOLDS,
        "skipped": [{"state": "scanning", "reason": "a scan's intermediate frames depend on timing; "
                     "the completed-scan state is checked instead"}],
        "styles": results,
        "findings": gate.findings,
        "checks": gate.checks,
        "failures": len(failures),
        "result": "PASS" if not failures else "FAIL",
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(f"GUI parity outputs: {out_dir}")
    if failures:
        print(f"FAIL: {len(failures)} of {len(gate.checks)} checks failed", file=sys.stderr)
        return 1 if strict else 0
    print(f"PASS: {len(gate.checks)} full-window checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
