# LinDirStat Agent Guide

## Project Purpose

LinDirStat is a GNUstep application intended to clone the WinDirStat experience as closely as practical for Linux and macOS.

The product goal is not just "a disk usage viewer." The target is the workflow and feel that make WinDirStat effective:

- scan a folder or volume and present a clear, actionable picture of disk usage
- keep the directory tree, file extension/type list, and treemap coordinated
- make size, percentage, file counts, colors, and selection state easy to understand
- support the familiar cleanup-oriented flow without surprising destructive behavior
- preserve WinDirStat-compatible behavior unless there is a platform reason not to

WinDirStat is open source and should be treated as the primary behavioral reference. Bring its source into this repository as reference material, preferably as a git submodule unless a later decision records why vendoring is better. Do not blindly port Windows/MFC-specific code, but use it to match data model behavior, scan semantics, UI interactions, color rules, and edge cases.

## Platform Strategy

- Primary platforms are Linux and macOS.
- Linux should use GNUstep/AppKit APIs and run naturally under GNUstep.
- macOS should be built on Apple's frameworks while keeping shared application logic portable where practical.
- Avoid Linux-only or macOS-only architecture decisions in shared code unless the boundary is explicit.
- Favor Objective-C and AppKit/GNUstep conventions over introducing unrelated UI stacks.

## GNUstep Tooling

Build, test and package against the gnustep-clang apt packages in `/usr/GNUstep` (see `docs/development.md`); the scripts select it through `scripts/gnustep-env.sh`, and `LINDIRSTAT_GNUSTEP_ROOT` picks another install. `~/git/gnustep/gnustep-cli-new` provides the `gnustep` CLI workflow on top of it.

Expected project operations:

- create or refresh GNUstep project structure through the `gnustep` CLI when available
- build with `gnustep build`
- run with `gnustep run`
- keep generated project files compatible with GNUstep Make unless the repo records a deliberate backend change

The Linux default theme target is Adwaita. The requested path was `~/git/gnustep/plugins-themes-Adwaita`, but the local checkout currently exists at:

`~/git/gnustep/plugins-themes-adwaita`

Prefer the local Adwaita GNUstep theme for Linux validation and document any setup steps needed to make it the default during development.

## Packaging Tooling

Use `~/git/gnustep/gnustep-packager` for packaging and distribution work.

Expected packaging operations:

- keep the downstream packaging contract in `package.manifest.json`
- use manifest-owned build and stage commands rather than app-specific ad hoc release scripts
- stage payloads into `dist/stage` with the packager layout: `app/`, `runtime/`, and `metadata/`
- package Linux releases through the AppImage backend
- keep macOS packaging separate until `gnustep-packager` grows a macOS DMG-style backend
- do not add ad hoc LinDirStat-only DMG packaging scripts; mature the backend in `~/git/gnustep/gnustep-packager` first, then enable it in `package.manifest.json`
- keep generated `dist/` and `out/` artifacts out of git
- declare Adwaita as the Linux packaged default theme with `GSTheme` using `ifUnset` semantics

## Product Priorities

1. Match WinDirStat behavior first, especially the three-pane workflow: directory tree, extension/type list, and treemap.
2. Keep scan correctness ahead of visual polish. Sizes, hard links, permissions failures, packages/bundles, symlinks, and filesystem boundaries must be explicit and testable.
3. Build the treemap as a real interactive visualization, not a static report.
4. Keep destructive cleanup actions deliberate, inspectable, and undo-resistant by design. Do not add one-click deletion flows without confirmation and platform trash support.
5. Preserve native platform expectations where they do not conflict with WinDirStat's core workflow.
6. Keep the app free of theming code. Under the Adwaita GNUstep theme it should look like a first-class GTK4 app purely through standard AppKit controls and system `NSColor`s; custom drawing is limited to WinDirStat content such as treemap cushions and percentage bars. Fix Adwaita rendering problems in the theme, not with app-side workarounds.

## Repository Practices

- Keep third-party reference source isolated under a clearly named path such as `vendor/WinDirStat` or `references/WinDirStat`.
- If using a submodule, record the upstream URL and pinned commit in the commit message and documentation.
- Do not mix large reference imports with unrelated application code changes.
- Add focused tests for scan logic, size aggregation, filtering, extension grouping, and treemap layout before treating those areas as stable.
- Use GNUstep's `tools-xctest` framework for Objective-C unit tests.
- Maintain comprehensive unit and regression coverage for model, scan, layout, UI coordination, platform integration, and user-visible workflows.
- New features and bug fixes are not complete until the relevant `tools-xctest` tests and regression tests are added or updated.
- Keep generated build artifacts out of git.

## GUI Review Process

GUI look and feel changes require an automated visual review loop before they are considered complete:

1. Build and run the app through `gnustep build` and `gnustep run` or the equivalent `gnustep-cli-new` workflow.
2. Launch the relevant screen with deterministic fixture data when possible.
3. Take an automatic screenshot of the app.
4. Have Codex inspect the screenshot image and review it for layout breakage, unreadable text, wrong control hierarchy, overlap, missing WinDirStat affordances, and mismatch with the intended Adwaita/GNUstep appearance.
5. Record the screenshot path and the review result in the development notes, PR, or final response for the change.

For Linux validation, run this review with the Adwaita GNUstep theme when available. For macOS validation, use Apple's native AppKit rendering and note any intentional platform differences.

## Coding Guidance

- Prefer small, testable model objects for filesystem scan state, directory aggregation, file type grouping, and treemap layout.
- Keep UI controllers thin; shared behavior should live in model or service classes that can be tested without launching the app.
- Treat permission errors, disappeared files, special files, symlink cycles, and concurrent filesystem changes as normal scan outcomes.
- Use platform abstractions for trash/reveal/open actions rather than scattering platform checks through UI code.

## Current Local Context

- The repository was initialized with `git init` in `/home/danboyd/git/LinDirStat`.
- `~/git/gnustep/gnustep-cli-new` exists locally and includes `new`, `build`, and `run` command support.
- The Adwaita theme checkout exists locally as `~/git/gnustep/plugins-themes-adwaita`.
- Local, non-tracked Codex/operator instructions live in `CODEX.local.md`.
- The implementation roadmap lives in `docs/implementation-roadmap.md`.
- Packaging notes live in `docs/packaging.md`.
