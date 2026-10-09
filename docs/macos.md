# macOS

LinDirStat builds natively on macOS against Apple's AppKit. GNUstep is not
used. Shared code is the same as on Linux; platform differences live in
small modules (`LDPlatformUI`, `LDHasher`, `LDVolumes`, `LDSystemInfo`,
`LDDesktop`, `LDFileOperations`, `LDFileTypeDescriptions`, `LDFileWatcher`,
`LDOpenWith`). `LDFileWatcherApple.m` and the Apple branch of `LDOpenWith.m`
are stubs (File Watcher unsupported, Open With empty) until the FSEvents and
NSWorkspace backends are written (parity plan M8, M9).

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
macOS. The version is `package.manifest.json`'s, and the build number is the
commit count. The app icon is drawn by `macos/icon/make-icon.swift` at build
time.

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
  other users' data and so on). They show as unreadable, and macOS may ask
  about Desktop, Documents and Downloads the first time. Grant it in System
  Settings › Privacy & Security › Full Disk Access for complete scans.
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

```sh
LINDIRSTAT_SCAN_PATH=/Applications/Xcode.app/Contents \
LINDIRSTAT_APPEARANCE=dark \
  macos/build/LinDirStat.app/Contents/MacOS/LinDirStat
```

`LINDIRSTAT_APPEARANCE` (`dark` or `light`) forces the appearance for
screenshots. Capture a window with `screencapture -l <window id>`.
