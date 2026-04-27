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
| Directory scan | partial | Recursive scanner, aggregation, error tracking, hard-link duplicate handling, and async session path exist. Large-tree performance and platform edge cases remain. |
| Directory tree pane | partial | Table is present with name, size, percent, and item count. Expand/collapse tree behavior, sorting UI, and selection sync remain. |
| Extension/type pane | partial | Extension grouping, counts, bytes, percent, and stable colors exist. Descriptions and color swatches remain. |
| Treemap pane | partial | Deterministic treemap rendering, labels, colors, and point lookup exist. WinDirStat's exact squarified layout and selection sync remain. |
| Status/progress | partial | Summary status exists. Live progress, cancel state, and elapsed time UI remain. |
| Folder/drive selection | deferred | Open action button is visible but not wired to a folder chooser yet. |

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

The parity gate uses deterministic fixture trees in `Tests/Fixtures/windirstat-parity/trees.json`. For each fixture and viewport size it renders:

- a LinDirStat treemap by building and invoking `Tools/windirstat-parity-exporter`, which constructs `LDFileNode` objects and calls production `LDTreemapLayout`
- a WinDirStat oracle treemap using KDirStat-style row squarification, the WinDirStat default palette family, and cushion-like shading
- rectangle JSON for both renderers
- a summary of geometry and image similarity metrics

Output is written to `dist/validation/windirstat-parity`, including `windirstat-oracle-metadata.json` to record oracle assumptions and limitations.

The metrics include rectangle coverage, pixel gaps/overlaps, file area proportionality, aspect-ratio drift, center-point drift, color histogram similarity, edge-density similarity, and pixel distance.

The gate is non-strict by default so existing work can measure visual drift without failing the full local regression flow. Strict mode is the target for claiming treemap visual parity:

```sh
WINDIRSTAT_PARITY_STRICT=1 ./scripts/windirstat-parity-gate.sh
```

Strict mode is expected to fail until the treemap implementation moves from simple alternating slices toward WinDirStat's KDirStat-style squarification and cushion-shaded rendering.

For full-window review, run:

```sh
./scripts/gui-parity-correlation.sh
```

When a GUI display and capture tools are available, the script captures a LinDirStat window screenshot and writes `dist/validation/gui-parity/correlation.json` linking that screenshot to the latest headless parity summary.
