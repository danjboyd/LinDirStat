# LinDirStat Implementation Roadmap

This roadmap is ordered by implementation dependency. The main line is to get a minimal GNUstep app running quickly, lock down scan/model correctness with tests, then build toward WinDirStat-level behavior and visual fidelity.

## Phase 1: Repository And Reference Baseline

### 1A. GNUstep Project Skeleton

- Provision the initial GNUstep application structure with `~/git/gnustep/gnustep-cli-new`.
- Confirm `gnustep build` and `gnustep run` work from a clean checkout.
- Add basic app metadata, icon placeholders, and GNUstep Make files.

### 1B. Test Harness

- Add a `tools-xctest` test target.
- Add a minimal smoke test for shared model code and a launch/build regression check.
- Document the local commands for build, run, and test.

### 1C. WinDirStat Reference Source

- Add WinDirStat as isolated reference material, preferably as a git submodule under `references/WinDirStat`.
- Pin the upstream commit and document the source URL.
- Identify the first reference areas to study: scan aggregation, extension list behavior, treemap layout, color assignment, and selection coordination.

### 1D. Fixture Data

- Add deterministic test fixture directory trees for scan and UI development.
- Include files with nested directories, duplicate extensions, extensionless files, hidden files, symlinks, hard links where supported, permission failures where testable, and disappearing-file scenarios.

## Phase 2: Core Domain Model

### 2A. Filesystem Node Model

- Implement directory and file node objects with path, display name, size, allocated size when available, file count, directory count, error state, and parent/child relationships.
- Keep the model independent from UI classes.

### 2B. Size Aggregation

- Implement recursive size aggregation and percentage calculations.
- Define behavior for unreadable paths, special files, symlinks, filesystem boundaries, packages/bundles, and hard links.
- Cover aggregation behavior with `tools-xctest`.

### 2C. Extension And Type Grouping

- Implement WinDirStat-style extension grouping with colors, descriptions, bytes, file counts, and percentage of total.
- Define handling for extensionless files, hidden files, case sensitivity, and compound names.
- Add regression tests against fixture trees.

### 2D. Scan Session State

- Add scan states for idle, scanning, paused if supported, complete, canceled, and failed.
- Track progress, current path, skipped/error counts, and elapsed time.
- Make state transitions testable without launching the app.

## Phase 3: Scanner Engine

### 3A. Synchronous Scanner

- Build a simple deterministic scanner over fixture directories.
- Emit model updates and error records.
- Prove correctness with tests before adding concurrency.

### 3B. Async Scanner

- Move scanning off the main thread while keeping UI updates on the main thread.
- Support cancellation and safe teardown.
- Add regression coverage for cancellation, errors, and mid-scan model updates.

### 3C. Platform Filesystem Details

- Add platform abstractions for stat calls, aliases/symlinks, hard-link identity, mount boundaries, hidden files, and package/bundle detection.
- Keep Linux/GNUstep and macOS differences behind narrow interfaces.

### 3D. Scan Persistence Hooks

- Prepare stable serialization or snapshot hooks for tests, bug reports, and future session restore.
- Do not add user-facing persistence until the model format is stable.

## Phase 4: Treemap Layout And Rendering

Initial execution status: implemented deterministic slice-and-dice treemap layout, stable extension color selection, a custom GNUstep/AppKit treemap view, and point-to-item selection lookup with `tools-xctest` coverage.

### 4A. Layout Algorithm

- Implement the treemap layout using a deterministic algorithm matched as closely as practical to WinDirStat behavior.
- Keep layout computation separate from drawing.
- Test rectangle coverage, ordering, minimum sizes, rounding, and stability.

### 4B. Color Assignment

- Match WinDirStat-style extension color behavior where possible.
- Ensure colors remain stable across rescans of the same data.
- Add tests for color grouping and fallback color selection.

### 4C. GNUstep Treemap View

- Implement a custom AppKit/GNUstep view for drawing treemap rectangles.
- Support selection, hover/highlight, keyboard focus, and invalidation without unnecessary full redraws.

### 4D. Treemap Interaction

- Wire treemap clicks to filesystem nodes and extension groups.
- Add tooltips or inspector details for selected files and directories.
- Regression-test selection mapping from points to model nodes.

## Phase 5: Main WinDirStat Interface

Initial execution status: implemented a first GNUstep three-pane application shell with directory rows, extension/type rows, and treemap view populated from deterministic scan data. Later phases still need full WinDirStat interaction fidelity, screenshot review, and richer controls.

### 5A. Window Shell

- Build the main window with directory tree, extension/type list, and treemap panes.
- Match WinDirStat's information density and pane relationships while respecting native GNUstep/AppKit controls.

### 5B. Directory Tree

- Implement sortable columns for name, size, percentage, item counts, and last modified date if supported.
- Keep tree selection synchronized with treemap selection.
- Add regression tests for sorting and selection coordination.

### 5C. Extension List

- Implement the extension/type list with color swatches, extension, description, bytes, percentage, and file count.
- Synchronize extension selection with treemap highlighting.

### 5D. Scan Controls And Status

- Add open folder/volume selection, rescan, stop/cancel, status bar, progress indication, and scan summary.
- Keep commands disabled/enabled according to scan state.

### 5E. GUI Screenshot Review Gate

- Add an automated way to launch the app with fixture data and capture a screenshot.
- Have Codex review the screenshot for visual regressions, layout overlap, unreadable text, missing controls, and WinDirStat fidelity.
- Store screenshots outside normal build artifacts or in an ignored diagnostics directory unless explicitly needed as test fixtures.

## Phase 6: File Actions And Safety

Initial execution status: implemented non-destructive reveal/open action plans, confirmation-required trash plans, and disabled permanent-delete plans with `tools-xctest` coverage. Actual platform execution remains intentionally behind the safety planning boundary.

### 6A. Reveal And Open

- Implement platform-specific reveal-in-file-manager and open actions behind a shared interface.
- Cover missing file, permission, and platform fallback behavior.

### 6B. Trash/Delete Workflow

- Prefer platform trash APIs over permanent deletion.
- Require confirmation, show exact targets, and avoid bulk destructive actions without a clear review step.
- Add regression tests for command enablement and action planning.

### 6C. Cleanup Command Compatibility

- Study WinDirStat cleanup commands and reproduce the useful workflow where safe on Linux and macOS.
- Record any intentional differences caused by platform trash, permissions, or security models.

## Phase 7: Look And Feel Fidelity

Initial execution status: improved the GNUstep UI with explicit WinDirStat-style pane labels, scan controls, path display, formatted sizes, percentages, status summary, and readable treemap labels. Added repeatable GUI screenshot capture for visual review.

### 7A. Adwaita GNUstep Theme Validation

- Document setup for `~/git/gnustep/plugins-themes-adwaita`.
- Validate Linux screenshots under the Adwaita GNUstep theme.
- Track any theme-specific control sizing or contrast issues.

### 7B. macOS Native Validation

- Validate the app using Apple's frameworks and native AppKit rendering.
- Keep core workflows consistent with Linux while allowing native menu, dialog, and file-picker conventions.

### 7C. WinDirStat Behavior Audit

- Compare major workflows against WinDirStat reference behavior.
- Maintain a checklist for scan results, tree columns, extension list behavior, treemap layout, colors, selection, and cleanup actions.

### 7D. Accessibility And Keyboard Use

- Add keyboard navigation for panes, menu commands, selection movement, and cancel/rescan.
- Validate readable labels, focus behavior, and accessible descriptions where GNUstep/AppKit supports them.

## Phase 8: Packaging And Distribution

Packaging and distribution should use `~/git/gnustep/gnustep-packager`. Keep the package contract in `package.manifest.json`, stage generated payloads under `dist/stage`, and use the AppImage backend for Linux distribution work. macOS packaging should become a DMG-style `gnustep-packager` backend; until that backend exists, document the requirement without adding LinDirStat-only DMG scripts.

### 8A. Linux Developer Packaging

- Package a developer AppImage through `gnustep-packager`.
- Build with `gnustep-cli-new`, stage through the manifest `stage` command, and validate the staged payload before backend packaging.
- Carry Adwaita as the default packaged GNUstep theme with `ifUnset` semantics.

### 8B. macOS Developer Packaging

- Produce a macOS app bundle with correct metadata and framework linkage.
- Mature `gnustep-packager` so it can produce a native macOS DMG-style package.
- Once the packager backend exists, enable the macOS target in `package.manifest.json`.
- Document signing/notarization expectations as part of the packager backend contract.
- Do not force macOS through the Linux AppImage packaging path or maintain one-off DMG scripts in this repo.

### 8C. Release Diagnostics

- Add diagnostic output for version, runtime, theme, scan settings, and platform filesystem behavior.
- Make bug reports reproducible without exposing private filesystem paths unnecessarily.

## Phase 9: Comprehensive Regression Gate

Initial execution status: added `scripts/regression-gate.sh` and `docs/regression-gate.md` covering build, `tools-xctest`, packager manifest/build/stage/validate, plus a window-only screenshot capture script for GUI review.

### 9A. Unit Test Expansion

- Expand `tools-xctest` coverage across scanner, aggregation, extension grouping, treemap layout, selection coordination, and platform action planning.

### 9B. Fixture-Based Regression Tests

- Add deterministic full-scan regression tests over fixture trees.
- Store expected summaries in a reviewable format.

### 9C. GUI Regression Screenshots

- Add repeatable screenshot capture for canonical app states: empty, scanning, complete scan, selected directory, selected extension, and error states.
- Use Codex image review for each GUI-affecting change.

### 9D. Cross-Platform Validation

- Define the minimum Linux and macOS validation matrix.
- Keep platform-specific failures documented with exact commands, screenshots, and logs.

## Phase 10: WinDirStat Parity Closure

Initial execution status: added `docs/windirstat-parity.md` to track matched, partial, deferred, and intentionally different behavior against the local WinDirStat reference source.

### 10A. Feature Parity Checklist

- Maintain a tracked checklist of WinDirStat features and behaviors.
- Mark each item as matched, intentionally different, deferred, or out of scope.

### 10B. Performance Tuning

- Profile large scans and treemap rendering.
- Optimize without weakening model clarity or testability.

### 10C. User Documentation

- Add concise documentation for scanning, reading the panes, cleanup actions, platform differences, and troubleshooting.

### 10D. Release Candidate Review

- Run build, test, scan regression, GUI screenshot review, and platform validation gates.
- Record known gaps before tagging a release candidate.

## Phase 11: Automated WinDirStat Visual Parity Gate

Initial execution status: added deterministic fixture specs, a standalone `scripts/windirstat-parity-gate.sh` runner, a Python renderer/comparator, non-strict metric reporting, strict-mode thresholds, and documentation in `docs/regression-gate.md` and `docs/windirstat-parity.md`. Subphases 11A-F are implemented with expanded fixtures, oracle metadata, a GNUstep headless exporter that calls the production `LDTreemapLayout` code, expanded geometry/image metrics, non-strict regression-gate integration, and GUI screenshot correlation output. Strict mode currently fails as expected because the app still uses a simple slice treemap rather than WinDirStat-style squarified, cushion-shaded rendering.

### 11A. Deterministic Visual Fixtures

Execution status: implemented.

- Maintain fixture trees that exercise balanced file mixes, many small files, deep nesting, zero-byte files, repeated extensions, and extreme size ratios.
- Render each fixture at multiple canonical treemap viewport sizes.
- Keep fixture data small, reviewable, and independent from the host filesystem.

### 11B. WinDirStat Oracle Renderer

Execution status: implemented as a deterministic test oracle with documented limitations.

- Keep the test oracle aligned with the local WinDirStat reference source for KDirStat-style row squarification, default palette behavior, grid handling, and cushion-shading parameters.
- Output oracle rectangle JSON and raster images for every fixture/viewport pair.
- Treat deviations from the reference source as documented test-oracle limitations, not silent assumptions.

### 11C. LinDirStat Headless Renderer

Execution status: implemented with `Tools/windirstat-parity-exporter`.

- Render LinDirStat treemap geometry and pixels without launching the full GUI.
- Prefer calling shared production layout/rendering code as the implementation matures, so the gate measures the actual app rather than a duplicate approximation.
- Output LinDirStat rectangle JSON and raster images next to the oracle outputs.

### 11D. Geometry And Image Metrics

Execution status: implemented.

- Compare area coverage, gaps, overlaps, file area proportionality, aspect-ratio distribution, center-point movement, palette similarity, and pixel-level image distance.
- Keep non-strict mode useful for tracking trend data while treemap parity remains incomplete.
- Make strict mode fail when visual similarity or geometry thresholds regress below the WinDirStat parity target.

### 11E. Regression Gate Integration

Execution status: implemented in non-strict mode.

- Keep the parity gate documented alongside the normal regression gate.
- Run non-strict mode for visual diagnostics during treemap and UI work.
- Enable strict mode as a required release-candidate check once Phase 4 and Phase 7 treemap fidelity work reaches the documented thresholds.

### 11F. GUI Screenshot Correlation

Execution status: implemented with opportunistic screenshot capture.

- Correlate headless parity outputs with full-window GUI screenshots from `scripts/capture-gui-review.sh`.
- Add canonical complete-scan screenshots once fixture path selection and UI state control are deterministic.
- Use the headless gate for precise numeric failures and GUI screenshots for whole-window layout fidelity.

## Phase 12: WinDirStat UI Fidelity Pass

Initial execution status: audit completed against local LinDirStat screenshots, supplied WinDirStat screenshots, WinDirStat documentation, and public screenshot references. Subphases 12A-C have an initial implementation: treemap layout is now squarified with WinDirStat-like saturated colors and cushion-style shading, pane proportions now favor the directory tree with a narrower extension legend, and the directory list is now an expandable outline with WinDirStat-style columns. Remaining fidelity work includes exact WinDirStat cushion rendering, extension legend details, scan-time tree animation, toolbar/menu chrome, status bar, and coupled selection behavior.

### 12A. Treemap Visual Rendering

Execution status: initial implementation complete; strict Phase 11 parity still fails on color/rendering fidelity.

- Replace flat slice-style rectangles with WinDirStat/KDirStat-style squarified nested treemap geometry.
- Implement cushion shading, ridge-like lighting, saturated extension colors, and dark separators that reveal directory structure.
- Remove default file-name labels from treemap rectangles unless a dedicated inspection/tooltip mode is active.
- Drive completion with the Phase 11 strict visual parity gate.

### 12B. Three-Pane Layout Proportions

Execution status: initial implementation complete.

- Rework the main window into WinDirStat's classic composition: wide directory tree on the upper left, narrower extension legend on the upper right, and full-width treemap on the bottom.
- Use split-view behavior or equivalent resizing so pane relationships remain stable across window sizes.
- Keep the treemap bottom band visually dominant and dense enough to resemble WinDirStat screenshots.

### 12C. Directory Tree Fidelity

Execution status: initial implementation complete.

- Replace flattened indentation with a real expandable/collapsible tree list.
- Add WinDirStat-style columns: subtree percentage bar, percentage, size, files, subdirs, items, last change, and attributes where available.
- Sort rows by subtree size descending within each expanded parent.
- During scanning, reserve the subtree percentage column for scan progress indicators.

### 12D. Extension List Legend Fidelity

- Add the WinDirStat extension-list columns: extension, color swatch, description, bytes, percent bytes, and file count.
- Assign colors to the top file types and grey out lower-ranked extensions, matching WinDirStat legend behavior.
- Keep the extension list sorted by bytes descending and visually usable as the treemap color legend.

### 12E. Scan-Time Animation And Incremental Updates

- Replicate WinDirStat's scan-time directory-tree animation, including a pacman-style indicator or read-job/progress display in the subtree percentage column.
- Show current path, elapsed scan state, and responsive stop/cancel behavior while scanning.
- Incrementally populate or update the directory tree during scan instead of showing only a final completed state.
- Capture reference behavior from a Windows WinDirStat run if public screenshots are insufficient for frame timing and per-row animation details.

### 12F. Toolbar, Menus, And Command Chrome

- Add the WinDirStat-style menu structure: File, Edit, Clean Up, Treemap, Report, Options, and Help.
- Add compact toolbar icon buttons for open, rescan, stop, cleanup/reveal actions, treemap zoom, and navigation commands.
- Match command enablement to scan state and current selection.
- Keep platform-specific actions safe while preserving WinDirStat workflow shape.

### 12G. Status Bar Fidelity

- Replace the single status label with a WinDirStat-style bottom status bar.
- Show left-aligned scan/ready messages and right-aligned diagnostic fields such as memory usage, selected size, scan summary, or keyboard/status indicators where meaningful.
- Ensure status text remains readable at the minimum window size.

### 12H. Coupled View Selection

- Synchronize directory tree, treemap, and extension list selections.
- Selecting a directory or file in the tree should frame the corresponding treemap item or subtree.
- Clicking a treemap rectangle should expand/select the file in the directory tree and select/scroll the matching extension row.
- Selecting an extension should highlight all files of that type in the treemap.

### 12I. Reference Capture And Screenshot Catalog

- Maintain a small catalog of WinDirStat reference screenshots and notes covering completed scan, active scan animation, extension selection, treemap selection, and cleanup/menu states.
- Prefer locally captured Windows reference material when exact animation timing or command behavior is ambiguous.
- Document source URLs and capture dates for public references, and keep copyrighted screenshots out of committed artifacts unless licensing permits.

### 12J. Full-Window UI Parity Gate

- Extend GUI screenshot review to compare full-window composition against the WinDirStat reference catalog.
- Add automated checks for pane proportions, visible columns, toolbar/menu/status presence, treemap density, and absence of text/control overlap.
- Use the full-window gate alongside the Phase 11 headless treemap gate before claiming WinDirStat UI fidelity.
