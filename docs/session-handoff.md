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

- Convert the project to ARC (clang + libobjc2 `gnustep-2.2` runtime supports `-fobjc-arc`).
- Step C, window chrome: `NSSplitView` panes, WinDirStat menus and toolbar, custom-drawn subtree-percentage cells with depth colors and pacman, file icons, sortable headers, compact rows, three-field status bar. Use standard controls and system colors only; see the look-and-feel principle in `AGENTS.md`.
- Step D onwards: clean-up actions (trash, open, reveal), refresh selected, drive picker, largest files, duplicates, search, CSV, filters, settings, dark mode.

## Known Gaps

- The subtree percent column is still ASCII text.
- Menus are minimal (File and Treemap only).
- Scanning is single-threaded.
