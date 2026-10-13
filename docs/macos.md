# macOS

LinDirStat builds natively on macOS against Apple's AppKit. GNUstep is not
used. Shared code is the same as on Linux; platform differences live in
small modules (`LDPlatformUI`, `LDHasher`, `LDVolumes`, `LDSystemInfo`,
`LDDesktop`, `LDFileOperations`, `LDFileTypeDescriptions`, `LDFileWatcher`,
`LDOpenWith`). The File Watcher uses FSEvents (`LDFileWatcherApple.m`) and
Open With uses `NSWorkspace` (parity plan M8, M9).

## Build

Needs Xcode or the Command Line Tools (macOS 13 or later to run).

```sh
make -C macos            # macos/build/LinDirStat.app (arm64 + x86_64)
make -C macos run        # build and open it
make -C macos test       # Tests/ as an Apple XCTest bundle
make -C macos zip        # macos/build/LinDirStat-<version>-macos.zip
make -C macos CONFIG=debug
```

The source list comes from `Source/GNUmakefile` and the test list from
`Tests/GNUmakefile`, so a file added to the GNUstep build is also built on
macOS. The UI coordination tests (`Tests/UI`) are not part of the macOS
build: they rely on Xvfb, the freedesktop.org trash under a private
`XDG_DATA_HOME` and GNUstep's defaults location, none of which isolate a
test run on macOS (it would use the user's real Trash). The version is `package.manifest.json`'s, and the build number is the
commit count. The app icon is drawn by `macos/icon/make-icon.swift` at build
time.

## DMG

The disk image is made by gnustep-packager's `dmg` backend from the staged
build, not by a script here:

```sh
pwsh ~/git/gnustep/gnustep-packager/scripts/run-packaging-pipeline.ps1 \
  -Manifest package.manifest.json -Backend dmg -RunSmoke
```

It builds with `make -C macos`, stages `dist/stage/app/LinDirStat.app`, and
writes `dist/packages/LinDirStat-0.1.0-macos-universal.dmg` (the app, an
Applications link and the license notices). The app keeps its ad-hoc
signature; notarization is off until there is a Developer ID. Details:
[packaging.md](packaging.md#macos-dmg).

## Signing without a Developer ID

There is no Apple Developer account, so the app is ad-hoc signed
(`codesign -s -`, hardened runtime) and not notarized. It runs normally on
the Mac that built it. On another Mac, Gatekeeper blocks the first launch of
a downloaded copy:

- macOS 15 and later: open it once, then System Settings › Privacy & Security
  › "Open Anyway".
- Or remove the quarantine flag: `xattr -dr com.apple.quarantine LinDirStat.app`.

Set `SIGN_ID` to sign with a real identity later (`make -C macos SIGN_ID="Developer ID Application: …"`).

The app is not sandboxed: a disk usage viewer needs to read the whole disk.

## Permissions

- **Full Disk Access.** Without it, macOS hides some folders (Mail, Safari,
  other apps' data and so on), and reading them fails with `EPERM`. Ordinary
  Unix permission errors are `EACCES`. They show as unreadable, and macOS
  may ask about Desktop, Documents and Downloads the first time.
  - After a scan that hit such folders, if the app lacks Full Disk Access
    (`LDPrivacyAccess`), a sheet offers to open System Settings › Privacy &
    Security › Full Disk Access. It appears once per launch and has a
    "Don't ask again" box. Help › Full Disk Access Settings… opens the same
    pane at any time.
  - Some system folders refuse even with Full Disk Access. The prompt only
    appears when access is missing.
- **Grants and ad-hoc signing.** macOS ties privacy grants (Full Disk Access,
  Automation) to the app's code signature. An ad-hoc signature changes with
  every build, so after rebuilding or updating, a grant may look enabled
  but no longer apply: remove LinDirStat from the list and add it again. A
  stable signing identity (`SIGN_ID`, even a self-signed code-signing
  certificate) keeps grants across builds.
- **Automation (Finder).** Clean Up › Empty Trash asks Finder to empty the
  Trash, which covers every volume's trash. The first time, macOS asks to let
  LinDirStat control Finder.

## Platform behaviour

- Toolbar uses SF Symbols, and the tree shows Finder's file icons. Type
  descriptions come from Uniform Type Identifiers.
- Menus follow macOS conventions:
  - Application menu: About, Settings ⌘,, Services, Hide, Quit.
  - Edit menu: the standard Undo through Select All, with Copy Path on ⌥⌘C.
  - Shortcuts: Move to Trash ⌘⌫, Delete Permanently ⌥⌘⌫, Refresh All ⌘R, Refresh Selected ⇧⌘R.
  - Window and Help menus.
- Move to Trash uses `NSFileManager` (Finder's Put Back works). The
  freedesktop.org trash code is Linux-only.
- The APFS System and Data volumes share a device number, so volume mount
  points are also detected with `statfs`. A scan of `/` then counts
  `/Users`, `/Applications` and other firmlinked folders where they appear,
  not under `/System/Volumes/Data`.
- The Select Target dialog lists volumes the way Finder does: local volumes
  that are not hidden (`MNT_DONTBROWSE`).
- Filenames must be valid UTF-8 on APFS and HFS+, so the tests that create
  other names on disk run on Linux only.

## GUI review

`make -C macos gui-gate` runs the full-window GUI parity gate
(`scripts/gui-parity-gate-macos.py`): the GNUstep gate's fixture, seven
states and checks, in light and dark, on the real screen. It never moves the
mouse or types into other apps: LinDirStat is driven through its own
accessibility elements by `macos/gui-gate/macgate.swift`, and screenshots are
of its window alone. It backs up the app's defaults domain, resets it for
each style and restores it, and refuses to run while LinDirStat is open.
The terminal needs Accessibility and Screen Recording permission. Output:
`dist/validation/gui-parity-macos` (screenshots, layouts, `summary.json`).

For a quick look by hand:

```sh
LINDIRSTAT_SCAN_PATH=/Applications/Xcode.app/Contents \
LINDIRSTAT_APPEARANCE=dark \
  macos/build/LinDirStat.app/Contents/MacOS/LinDirStat
```

`LINDIRSTAT_APPEARANCE` (`dark` or `light`) forces the appearance for
screenshots. Capture a window with `screencapture -l <window id>`.
