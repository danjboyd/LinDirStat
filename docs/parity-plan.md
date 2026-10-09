# WinDirStat Parity Plan

The remaining gaps to full WinDirStat parity, split between the two
sessions. Each item gets its own branch and a PR to `main`. The other session
checks every PR on its own platform before it is merged.

- **Linux** is the "LinDirStat" session on the Linux machine.
- **macOS** is the "LinDirStat macOS" session.

## Rules

- `AppController*.m` is owned by **Linux**. **macOS** changes to it go
  through `LDPlatformUI` or `macos/`, or are announced before starting.
- Shared features that need platform code define an interface. **Linux**
  writes it with its Linux backend, **macOS** writes the Apple backend.
- Whoever merges a PR updates the Status column here.
- Every PR keeps `./scripts/run-tests.sh` and the parity gate green on Linux
  and `make -C macos test` green on macOS, and adds tests for what it
  changes.

## Shared features (both builds)

| # | Gap | Owner | Status |
|---|---|---|---|
| L1 | Show Free Space / Show Unknown (F6/F7): `<Free Space>` and `<Unknown>` under volume roots, WinDirStat's lighter/darker colour flags in `LDTreemap` | Linux | todo |
| L2 | Hard links: `<Hardlinks>` pseudo-folder and ⧉ marker that jumps between links; Refresh Selected keeps the scan's hard-link set; CSV restores hard-link physical sizes and writes real Index values | Linux | PR |
| L3 | Command line: `--savetocsv`, `--savedupestocsv`, `--loadfromcsv` | Linux | todo |
| L4 | Scan progress: percent bar in the status bar and "NN%" title for volume roots, per-row time spent, pacman "zzz" when a folder stalls | Linux | todo |
| L5 | Preferences: treemap grid and highlight colour pickers with a live preview; subtree bar level colours and level count; "Automatically resize columns" | Linux | todo |
| L6 | Chrome: Show Toolbar, Show Status Bar, Large Toolbar Icons; Ctrl+F1–F4 tab shortcuts and Tab cycling into the extension list; Expand/Collapse as the tree context menu's default item; Name sorts by type first; Empty Trash label "(N Items, X)"; Help menu (manual, report a bug) | Linux | todo |
| L7 | Duplicates found during the scan, not after it | Linux | todo |
| L8 | File Watcher tab (Tools › Start File Watcher): `LDFileWatcher` interface, inotify backend, tab UI | Linux | todo |
| M8 | File Watcher FSEvents backend for `LDFileWatcher` | macOS | blocked on L8 interface |
| L9 | "Open With" submenu in place of WinDirStat's Explorer menu: `LDOpenWith` interface, Linux backend (desktop entries / `gio`), menu UI | Linux | todo |
| M9 | "Open With" Apple backend (`NSWorkspace` application URLs) | macOS | blocked on L9 interface |
| M5 | Localization (WinDirStat's Language setting): `.lproj` string tables shared by both builds; done last because it touches every UI string | macOS | after L1–L9 |

## Platform work

| # | Gap | Owner | Status |
|---|---|---|---|
| L10 | Linux AppImage: fix `gnustep-packager` for apps without file associations, then package | Linux | todo |
| M1 | macOS distribution: DMG through `gnustep-packager`'s `dmg` backend (AGENTS.md: no ad hoc DMG scripts); signing pipeline ready for a Developer ID and notarization once there is one | macOS | todo |
| M2 | Full Disk Access: detect missing access and guide the user to System Settings | macOS | todo |
| M3 | Apple backends for anything new in L1–L9 that needs one (free space, progress range, hard links on APFS clones) | macOS | as PRs land |

## Quality gates

| # | Gap | Owner | Status |
|---|---|---|---|
| L11 | Full-window parity gate (roadmap 12J) on Linux: pane proportions, columns, chrome, overlap checks against the reference catalog | Linux | todo |
| M11 | The same full-window review on macOS | macOS | after L11 |
| L12 | Automated UI coordination tests (selection sync, refresh, deletion, tab lists) | Linux | todo |
| L13 | Performance: profile and fix stop/finalize time on million-file scans and duplicate detection memory | Linux | todo |
| M13 | macOS validation matrix (macOS 13–26, Intel and Apple Silicon where available) | macOS | todo |

## Intentional differences (not gaps)

Properties panel, POSIX regular expressions in Search, Logical Size off by
default on Linux, custom cleanup paths passed as arguments, and the
Windows-only cleanups. See `docs/windirstat-parity.md`.
