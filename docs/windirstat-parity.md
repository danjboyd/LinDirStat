# WinDirStat Parity Checklist

This checklist tracks LinDirStat against the local WinDirStat reference source in `references/WinDirStat`.

Status values:

- `matched`: implemented and covered enough to rely on
- `partial`: present but not complete
- `deferred`: planned but not started
- `different`: intentionally different, with rationale

## Core Workflow

| Area | Status | Notes |
| --- | --- | --- |
| Directory scan | partial | Background scanner using `fstatat`, staying on the root filesystem (mount points are shown but not entered), counting hard links once, recording physical (`st_blocks`) and logical sizes, mtime and mode. Directories are read by a pool of 4 libdispatch workers (WinDirStat's default threads per drive); children are sorted once after the scan. Completion is delivered on the main queue and Stop returns partial results. Exclusion filters, symlink following, refresh-selected and suspend/resume remain. |
| Size semantics | matched | Physical size by default like WinDirStat; Treemap > Use Logical Size switches every pane. Directories contribute no bytes of their own. |
| Directory tree pane | partial | Expandable outline with WinDirStat's columns (Name, Subtree Percentage, Percentage, Size, Files, Last Change), sortable headers (WinDirStat's directions), symbolic folder/file/link/mount icons, depth-indented percentage bars, dimmed unreadable folders and mount points, coupled with the treemap. Different: one Size column following Use Logical Size instead of separate physical and logical columns, which do not fit at GNOME's metrics; depth colours use GNOME's palette in WinDirStat's order. Remaining: live tree and pacman while scanning, column visibility options. |
| Extension/type pane | matched | Rank-based WinDirStat colours with cushioned swatches, descriptions from shared-mime-info, bytes, % bytes, files, sortable headers; selecting an extension highlights its files in the treemap. |
| Treemap pane | matched | Port of `CTreeMap`: KDirStat (default) and SequoiaView layouts, cushion shading with WinDirStat's real defaults, equalized palette, top-17 rank colors with grey for the rest, optional grid, white selection frame, extension highlighting, zoom in/out/reset with a frame, hover path in the status bar, double-click zoom, middle-click reset, wheel select-parent, dimming while scanning and while a resize settles. Pixel-identical to the oracle in the parity gate. Treemap settings UI, Show Free Space/Unknown remain. |
| Status/progress | matched | Status bar with spinner and live counts while scanning, hovered or selected path, selection size and memory use (WinDirStat's three panes). |
| Window chrome | matched | GNOME header bar with a toolbar (Select Target, Refresh, Stop, Select Parent, Zoom Out, Zoom In) and the primary menu (File, Edit, Treemap), split views with WinDirStat's proportions, saved window, pane and column sizes. Drawn entirely by the Adwaita GNUstep theme from standard controls. |
| Folder/drive selection | partial | Select Target opens a folder chooser. WinDirStat's drive list with usage bars remains. |
## File Actions

| Area | Status | Notes |
| --- | --- | --- |
| Reveal in file manager | partial | Safe action plan exists; platform execution remains. |
| Open file | partial | Safe action plan exists; platform execution remains. |
| Move to trash | partial | Confirmation-required action plan exists; platform trash execution remains. |
| Permanent delete | different | Disabled by default until a dedicated reviewed workflow exists. This is intentionally stricter than classic cleanup tools. |
| Cleanup commands | deferred | Needs WinDirStat reference audit before implementation. |

## Platform And Packaging

| Area | Status | Notes |
| --- | --- | --- |
| Linux GNUstep build | partial | Builds through `gnustep-cli-new`. |
| Linux Adwaita default | partial | Manifest declares Adwaita as packaged default with `ifUnset`; full packaged theme payload validation remains. |
| Linux AppImage | partial | `gnustep-packager` manifest/build/stage/validate path exists. Full AppImage packaging is currently blocked by packager handling of apps with no MIME/file associations. |
| macOS app | deferred | Apple-framework implementation and native validation remain. |
| macOS DMG packaging | deferred | Requires a new `gnustep-packager` macOS DMG-style backend. |

## Quality Gates

| Area | Status | Notes |
| --- | --- | --- |
| Unit/regression tests | partial | `tools-xctest` covers model, scan, layout, formatting, and action planning. More UI coordination tests remain. |
| GUI screenshot review | partial | Window-only capture script exists; screenshots must be reviewed for GUI-affecting changes. |
| Cross-platform validation | deferred | Linux local validation exists. macOS validation matrix remains. |
| Performance profiling | deferred | Needed for large directory scans and large treemaps. |

## Automated Visual Parity

Run:

```sh
./scripts/windirstat-parity-gate.sh
```

The gate renders each fixture in `Tests/Fixtures/windirstat-parity/trees.json` at three viewport sizes with the production renderer (`Tools/windirstat-parity-exporter --ppm`, which calls `LDTreemap` and the rank-based palette) and with an independent Python port of WinDirStat's `CTreeMap` (`references/WinDirStat/windirstat/Controls/TreeMap.cpp`). It is strict by default: any leaf rectangle difference, any channel drift above 2, or under 99.9% exact pixels fails. Current status: all fixtures match exactly.

Output is written to `dist/validation/windirstat-parity`, including both images, a diff image, rectangle JSON and `summary.json`.

For full-window review, run:

```sh
./scripts/gui-parity-correlation.sh
```
