# Regression Gate

Run the full local regression gate with:

```sh
./scripts/regression-gate.sh
```

The gate covers:

- `gnustep-cli-new` build execution
- `tools-xctest` bundle build
- `tools-xctest` unit/regression execution
- strict WinDirStat treemap parity (production renderer vs. WinDirStat oracle)
- strict full-window GUI parity on a private Xvfb (`scripts/gui-parity-gate.sh`)
- `gnustep-packager` manifest validation
- `gnustep-packager` build
- `gnustep-packager` stage
- `gnustep-packager` shared validation

WinDirStat visual parity can be measured with:

```sh
./scripts/windirstat-parity-gate.sh
```

That gate renders every fixture in `Tests/Fixtures/windirstat-parity/trees.json` at each canonical size twice: once with the production `LDTreemap` renderer (through `Tools/windirstat-parity-exporter --ppm`) and once with an independent Python port of WinDirStat's `CTreeMap` (KDirStat layout, cushion shading, equalized palette, rank-based extension colors). Both use the same double-precision math, so the gate is strict by default and fails on any leaf rectangle difference, any pixel channel drift above 2, or less than 99.9% exact pixel matches.

Outputs in `dist/validation/windirstat-parity` include both PPM images, a red diff image per case, rectangle JSON, and `summary.json`. To record metrics without failing (for example while deliberately changing the renderer and the oracle together):

```sh
WINDIRSTAT_PARITY_STRICT=0 ./scripts/windirstat-parity-gate.sh
```

The whole window is checked headless with:

```sh
./scripts/gui-parity-gate.sh
```

It needs `Xvfb`, `xdotool` and ImageMagick (`import`, `convert`), starts its own X display (the first free one from `:90`; `GUI_PARITY_DISPLAY=:N` picks one) and runs the app with a private `GNUSTEP_HOME`, so it never touches your display or defaults. The app runs on a generated fixture (`Tests/Fixtures/gui-parity/tree.json`) in the light and dark styles through seven states: completed scan, extension selected, tree selection framed, Largest Files, Duplicate Files, context menu and Preferences. Each state is checked against the geometry the app reports through `LINDIRSTAT_DUMP_LAYOUT` (pane proportions, WinDirStat's columns and menus in order, toolbar, status bar, overlapping views, clipped column titles, treemap density) and against a screenshot (not blank, Adwaita header bar and list colours for the style, treemap pixels and rectangles equal to the Phase 11 renderer, selection and highlight frames). Output in `dist/validation/gui-parity`: per-style screenshots and layout JSON for each state, treemap crops and diffs, and `summary.json` with every check and non-failing findings. Strict by default; record without failing with:

```sh
GUI_PARITY_STRICT=0 ./scripts/gui-parity-gate.sh
```

Headless parity output can be correlated with a full-window GUI screenshot with:

```sh
./scripts/gui-parity-correlation.sh
```

GUI-affecting changes must also capture a window-only screenshot:

```sh
./scripts/capture-gui-review.sh /tmp/lindirstat-gui-review.png
```

Codex should inspect that image for overlap, unreadable labels, missing panes, broken table layout, treemap rendering problems, and deviations from the intended WinDirStat-style workflow.
