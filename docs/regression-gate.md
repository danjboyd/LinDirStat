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

Headless parity output can be correlated with a full-window GUI screenshot with:

```sh
./scripts/gui-parity-correlation.sh
```

GUI-affecting changes must also capture a window-only screenshot:

```sh
./scripts/capture-gui-review.sh /tmp/lindirstat-gui-review.png
```

Codex should inspect that image for overlap, unreadable labels, missing panes, broken table layout, treemap rendering problems, and deviations from the intended WinDirStat-style workflow.
