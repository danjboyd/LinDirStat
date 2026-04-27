# Regression Gate

Run the full local regression gate with:

```sh
./scripts/regression-gate.sh
```

The gate covers:

- `gnustep-cli-new` build execution
- `tools-xctest` bundle build
- `tools-xctest` unit/regression execution
- non-strict WinDirStat visual parity metric generation
- `gnustep-packager` manifest validation
- `gnustep-packager` build
- `gnustep-packager` stage
- `gnustep-packager` shared validation

WinDirStat visual parity can be measured with:

```sh
./scripts/windirstat-parity-gate.sh
```

That gate writes deterministic treemap oracle images, LinDirStat images, rectangle JSON, and a summary to `dist/validation/windirstat-parity`. It runs in non-strict mode by default because the current treemap is still intentionally tracked as partial parity. Use strict mode when changing treemap layout or rendering:

```sh
WINDIRSTAT_PARITY_STRICT=1 ./scripts/windirstat-parity-gate.sh
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
