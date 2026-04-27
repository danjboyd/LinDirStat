# Packaging

LinDirStat uses `~/git/gnustep/gnustep-packager` for packaging and distribution.

The downstream package contract lives in:

`package.manifest.json`

Current packaging scope:

- Linux packaging should use the `appimage` backend.
- Windows MSI is disabled for this project unless explicitly revisited.
- macOS packaging is planned, but `gnustep-packager` does not currently have a macOS target.

## Current AppImage Blocker

The LinDirStat manifest builds, stages, and passes shared validation. Full AppImage packaging currently fails in `gnustep-packager` when the app has no file associations:

`Cannot bind argument to parameter 'MimeEntries' because it is an empty array.`

LinDirStat should not declare a fake document type to work around this. The AppImage backend should mature to support applications with no MIME/file associations.

See `docs/gnustep-packager-upstream-requests.md`.

## macOS Packaging Direction

The intended macOS distribution shape is a native macOS `.dmg` installer or disk image built around Apple's frameworks and app bundle conventions.

Do not add ad hoc macOS DMG scripts directly to LinDirStat. The packaging path should mature in `gnustep-packager` first, then LinDirStat should enable the macOS backend in its manifest once that backend exists.

Expected future `gnustep-packager` capabilities:

- a macOS backend, likely named `dmg` or `macos-dmg`
- native `.app` bundle staging rules
- DMG layout configuration
- code signing and notarization hooks
- validation for bundle metadata, launch behavior, signing state, and packaged defaults

Until that exists, keep macOS packaging requirements documented here and keep the manifest valid against the currently supported packager schema.
