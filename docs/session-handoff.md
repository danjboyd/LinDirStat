# Session Handoff

Last updated: 2026-04-27

## Current State

LinDirStat has a working GNUstep app shell, filesystem scanner, extension statistics, treemap model/view, basic packaging scripts, regression tests, and a WinDirStat visual-parity harness. The roadmap is current through Phase 12.

Phase 11 is implemented as a non-strict visual parity gate:

- `scripts/windirstat-parity-gate.sh` renders canonical fixture treemaps and records geometry/image metrics.
- `Tools/TreemapParityExporter.m` exports production treemap rectangles for fixtures or a real path.
- `scripts/capture-path-treemap.sh` can scan a real directory, export the treemap, and render a PNG for review.
- Strict parity is intentionally not enabled yet because visual rendering is still short of WinDirStat.

Phase 12 was added for WinDirStat UI fidelity. Subphases 12A-C have initial implementation:

- `12A`: treemap geometry is now squarified, labels are hidden, extension colors are more saturated, and rendering has basic cushion-style shading on a black background.
- `12B`: the main window proportions now favor the directory tree with a narrower extension list, closer to WinDirStat.
- `12C`: the directory pane is now an expandable outline view with WinDirStat-style columns.

## Verified Before Stopping

The latest verification passed:

```sh
make -C Source
make -C Tests
LD_LIBRARY_PATH="$HOME/git/Arlen/vendor/tools-xctest/XCTest/obj:${LD_LIBRARY_PATH:-}" "$HOME/git/Arlen/vendor/tools-xctest/obj/xctest" Tests/LinDirStatTests.bundle
./scripts/windirstat-parity-gate.sh
```

The XCTest suite passed all 7 tests. The visual parity gate passes in non-strict mode. Recent treemap metrics showed full area coverage, no gap pixels, low overlap, and a much improved aspect-ratio delta, but low color histogram similarity remains a clear indicator that the WinDirStat cushion/palette look is not finished.

## Where To Resume

Start with Phase 12D-F:

- `12D`: make the extension list look and behave like the WinDirStat legend, including a color swatch column, descriptions, bytes, percent bytes, file count, top-extension coloring, and grey fallback.
- `12E`: replace the current simple async status spinner with WinDirStat-like scan-time directory animation, including a pacman/read-job indicator in the subtree percent column and incremental tree updates while scanning.
- `12F`: add WinDirStat-style menus and compact toolbar command chrome.

Useful WinDirStat reference source now exists as a submodule under `references/WinDirStat`. Likely files to inspect next:

- `references/WinDirStat/windirstat/Controls/TreeMap.cpp`
- `references/WinDirStat/windirstat/Controls/ExtensionListControl.cpp`
- `references/WinDirStat/windirstat/Controls/FileTreeControl.cpp`
- `references/WinDirStat/windirstat/Controls/PacMan.cpp`
- `references/WinDirStat/windirstat/Views/TreeMapView.cpp`

## Known Gaps

- Treemap rendering is still an approximation. It needs closer cushion shading and palette behavior before strict visual parity should pass.
- Extension list is still table-driven but not yet a faithful WinDirStat legend.
- Scan animation currently reports status and spinner text, but does not yet animate rows like WinDirStat.
- Toolbar, menus, status bar fields, and coupled tree/treemap/extension selection are still pending Phase 12 work.
- The app was tested live against `/home/danboyd`; the scan can be launched through `scripts/run-home-live.sh`, but GUI capture/review is still manual.
