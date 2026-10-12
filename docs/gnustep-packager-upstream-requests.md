# GNUstep Packager Upstream Requests

LinDirStat depends on `~/git/gnustep/gnustep-packager` for packaging.

## AppImage: Apps Without File Associations

Status: fixed and merged upstream (gnustep-packager #8, 2026-10-12).

The AppImage backend passed the empty MIME entry list of an app with no
`integrations.fileAssociations` into mandatory `[psobject[]]` parameters,
which PowerShell rejects:

`Cannot bind argument to parameter 'MimeEntries' because it is an empty array.`

The fix allows the empty collection in the three MIME helpers. With no
associations the backend writes no MIME package, omits `MimeType` from the
desktop entry and uses `Exec=AppRun`. The branch adds a Linux Pester case
(`tests/linux/AppImageBackend.Tests.ps1`, "packages an app that declares no
file associations") and documents the behaviour in
`docs/appimage-metadata-mapping.md`. LinDirStat declares
`"fileAssociations": []` and no placeholder types.

## AppImage: Packaged Default Theme Domain

`packagedDefaults.defaultTheme` makes `AppRun` write `GSTheme` into the
`packagedDefaults.appDomain.domain` defaults domain, which defaults to
`package.id`. GNUstep's application domain is the process name
(`LinDirStat`), not the package id, so the write has no effect unless the
manifest also declares an `appDomain` with the process name, and `appDomain`
requires at least one value. Writing `GSTheme` into the app domain would also
override a theme the user chose in `NSGlobalDomain`, which is not `ifUnset`.

LinDirStat instead stages `runtime/etc/GNUstep/GlobalDefaults.plist` next to a
relocatable `GNUstep.conf`; gnustep-base ranks it below the user's defaults.

Expected behavior: a packager-owned way to seed GNUstep defaults below the
user's domains (a generated `GlobalDefaults.plist` beside a relocatable
`GNUstep.conf`), or at least an app domain that defaults to the launch entry's
process name.

## AppImage: Relocatable GNUstep Runtime

The backend leaves dependency closure to the consumer. LinDirStat's stage
script walks `NEEDED` entries, copies libraries, writes a relative
`GNUstep.conf`, and needs `LD_LIBRARY_PATH` because most toolchain libraries
have no `RUNPATH` to rewrite (there is no `patchelf` on the build host).
`LD_LIBRARY_PATH` then leaks into processes the app starts.

Expected behavior: a shared helper (or a `gnustep-cli-new` staging command)
that stages a GNUstep runtime from an install with a host-library exclude
list, sets `$ORIGIN` `RUNPATH`s, and writes the relocatable `GNUstep.conf`, so
each app does not carry its own copy of this logic.

## AppImage: Smoke Validation Display

`validate -Backend appimage -RunSmoke` launches the AppImage on the caller's
`$DISPLAY`. A manifest option for the smoke display (or running it under its
own Xvfb) would keep validation off the developer's desktop.

## macOS: DMG Backend

Current gap:

`gnustep-packager` does not currently have a macOS target.

Expected future capability:

- a native macOS DMG-style backend
- `.app` bundle staging support
- DMG layout configuration
- code signing and notarization hooks
- validation for bundle metadata, launch behavior, signing/notarization state, and packaged defaults

LinDirStat should enable this backend in `package.manifest.json` once the backend exists.
