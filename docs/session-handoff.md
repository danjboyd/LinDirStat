# Session Handoff

Last updated: 2026-10-08

## Current State

Audit Steps A (scan correctness/performance) and B (WinDirStat treemap) are done.

Step A:

- `LDScanner` uses `fstatat`, stays on the root filesystem (mount points are recorded, not entered), counts hard links once, and records physical and logical sizes, mtime and mode. Nodes store names only; paths are derived from parents.
- Children are sorted once on the scan thread (`-[LDFileNode sortChildrenByMetric:]`); the outline reads them directly.
- `LDScanSession` is thread-safe (locked path/root, atomic counters) and exposes live progress.
- Physical size is the default; Treemap > Use Logical Size switches all panes.
- `/usr/share/doc` (45k files) now scans and displays in about 2 s; previously 15-20 s with a frozen window.

Since then:

- The project builds with ARC.
- Scanning uses a libdispatch worker pool (`-[LDScanner threadCount]`, default 4) and the session reports completion on the main queue.
- Memory follows WinDirStat's `CItem` layout: lean file nodes, directory-only state in `LDDirectoryNode`, names in per-worker `LDNameArena`s owned by the root, and 24-byte treemap cells. About 146 bytes per entry including the treemap (was ~335); `/usr` uses 166 MB in the app.
- The Adwaita shadow and rounded corners need the theme's patched libs-back; see `docs/development.md`.

Step C (window chrome):

- `Info-gnustep.plist` declares GNOME metrics, the primary menu and the toolbar in the header bar; the theme draws all chrome.
- Symbolic icons come from the Adwaita icon theme via `scripts/generate-symbolic-icons.py` (see `Source/Resources/Icons/README.md`).
- `LDTreeCells` draws the percentage bars and icon+name cells; `LDTreeSorting`, `LDFileTypeDescriptions` and `LDSystemInfo` hold the model-side logic.

Step B:

- `LDTreemap` (in `LDTreemapLayout.m`) is a port of WinDirStat's `CTreeMap`: KDirStat and SequoiaView layouts, cushion shading with the real defaults, the equalized palette and rank-based colors.
- `LDTreemapView` caches the rendered bitmap and adds WinDirStat's selection frame, extension highlighting, zoom (frame in the theme's selection color), hover, double-click zoom, middle-click reset, wheel select-parent, and dimming while scanning or resizing.
- The parity gate compares production pixels with an independent Python port of `CTreeMap` and is strict by default; every fixture matches exactly.

## Verify

```sh
./scripts/run-tests.sh
./scripts/windirstat-parity-gate.sh
make -C Source && LINDIRSTAT_SCAN_PATH=/usr/share/doc openapp Source/LinDirStat.app
```

## Where To Resume

- Step C leftovers: live tree updates and WinDirStat's pacman while scanning (needs the scanner to publish partial trees safely), column visibility options.
- Step D onwards: clean-up actions (trash, open, reveal), refresh selected, drive picker, largest files, duplicates, search, CSV, filters, settings, dark mode.

## Known Gaps

- Clean Up and Options menus wait for Step D/E.
- Theme notes for the Adwaita agent: GNUstep column autoresizing is worked around by fitting the Name and Description columns by hand; NSScrollView's header corner view is removed so overlay scrollbars do not hide the last column title.
- File actions (step D) must open paths from `-[LDFileNode nameBytes]` chains rather than `-path`, which is lossy for names that are not valid UTF-8.
