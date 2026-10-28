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
| L1 | Show Free Space / Show Unknown (F6/F7): `<Free Space>` and `<Unknown>` under volume roots, WinDirStat's lighter/darker colour flags in `LDTreemap` | Linux | done (#7) |
| L2 | Hard links: `<Hardlinks>` pseudo-folder and ⧉ marker that jumps between links; Refresh Selected keeps the scan's hard-link set; CSV restores hard-link physical sizes and writes real Index values | Linux | done (#7) |
| L3 | Command line: `--savetocsv`, `--savedupestocsv`, `--loadfromcsv` | Linux | done (#7) |
| L4 | Scan progress: percent bar in the status bar and "NN%" title for volume roots, per-row time spent, pacman "zzz" when a folder stalls | Linux | done (#11) |
| L5 | Preferences: treemap grid and highlight colour pickers with a live preview; subtree bar level colours and level count; "Automatically resize columns" | Linux | done (#11) |
| L6 | Chrome: Show Toolbar, Show Status Bar, Large Toolbar Icons; Ctrl+F1–F4 tab shortcuts and Tab cycling into the extension list; Expand/Collapse as the tree context menu's default item; Name sorts by type first; Empty Trash label "(N Items, X)"; Help menu (manual, report a bug) | Linux | done (#11) |
| L7 | Duplicates found during the scan, not after it | Linux | done (#7) |
| L8 | File Watcher tab (Tools › Start File Watcher): `LDFileWatcher` interface, inotify backend, tab UI | Linux | done (#7) |
| M8 | File Watcher FSEvents backend for `LDFileWatcher` | macOS | done (#9) |
| L9 | "Open With" submenu in place of WinDirStat's Explorer menu: `LDOpenWith` interface, Linux backend (desktop entries / `gio`), menu UI | Linux | done (#7) |
| M9 | "Open With" Apple backend (`NSWorkspace` application URLs) | macOS | done (#10) |
| M5 | Localization (WinDirStat's Language setting): `.lproj` string tables shared by both builds; done last because it touches every UI string | macOS | done (#18) |

## Platform work

| # | Gap | Owner | Status |
|---|---|---|---|
| L10 | Linux AppImage: fix `gnustep-packager` for apps without file associations, then package | Linux | done (gnustep-packager #8; AppImage validated against packager main 3e487ab) |
| M1 | macOS distribution: DMG through `gnustep-packager`'s `dmg` backend (AGENTS.md: no ad hoc DMG scripts); signing pipeline ready for a Developer ID and notarization once there is one | macOS | done (#20, gnustep-packager #10; packager main 3e487ab green on Linux, Windows and macOS) |
| M2 | Full Disk Access: detect missing access and guide the user to System Settings | macOS | done (#3) |
| M3 | Apple backends for anything new in L1–L9 that needs one (free space, progress range, hard links on APFS clones) | macOS | done (#12, #17) |
| L14 | "Open With LinDirStat" on folders in file managers, in place of WinDirStat's Explorer entry: the AppImage's desktop entry lists `inode/directory` | Linux | in review |

## Quality gates

| # | Gap | Owner | Status |
|---|---|---|---|
| L11 | Full-window parity gate (roadmap 12J) on Linux: pane proportions, columns, chrome, overlap checks against the reference catalog | Linux | done (#14) |
| M11 | The same full-window review on macOS | macOS | done (#16) |
| L12 | Automated UI coordination tests (selection sync, refresh, deletion, tab lists) | Linux | done (#13, #14) |
| L13 | Performance: profile and fix stop/finalize time on million-file scans and duplicate detection memory | Linux | done (#15) |
| M13 | macOS validation matrix (macOS 13–26, Intel and Apple Silicon where available) | macOS | deferred: needs Dan's Intel Mac (older macOS) |

## 0.1.5: WinDirStat 2.6–2.9 catch-up (milestone 0.1.5)

Items 0–7 (#58–#65) are done. The rest is split by who owns the code:
`AppController*.m` work goes to **Linux**, shared model and treemap
drawing to **macOS**. A Mac-affecting PR is checked on macOS before merge,
and a treemap PR on Adwaita.

| Issue | Gap | Owner | Reviewer | Status |
|---|---|---|---|---|
| #71 | CSV fixtures from WinDirStat 2.9.3 and newer (ScanOutcome/ScanError); duplicates' Sampled hash; sizes stay at 1 decimal | Linux | — | in review (#86) |
| #85 | A loaded Windows CSV joins paths with "/", so saving and loading it again fails | Linux | — | |
| #66 | Extension list: double-click searches; group unregistered extensions (UTType backend on macOS) | Linux | macOS (backend) | |
| #69 | File Watcher: regex quick filter, toolbar controls, autoscroll | Linux | — | |
| #67 | Seconds in timestamps; several folders in Select Target; any number of custom cleanups | Linux | macOS (part b) | |
| #83 | Header sorted by clicking keeps room for its sort arrow on macOS | Linux | macOS | |
| #57 | Treemap is solid black on an unreadable 0 B root | macOS | Linux (Adwaita) | |
| #68 | JSON save and load in upstream's format | macOS | Linux | |
| #70 | Treemap folder frames, headers, style presets (Hilbert/Moore stretch, may move to 0.1.6) | macOS | Linux (Adwaita) | |

The release itself (tag, AppImage, DMG) waits for Dan's approval.

### Release checklist

The steps follow 0.1.4's (#51–#55, `docs/packaging.md`, `docs/updates.md`).

1. Every issue above is closed. `./scripts/run-tests.sh`, the WinDirStat and
   GUI parity gates, and `make -C macos test` are green on `main`.
2. Release notes PR: finish `packaging/linux/release-notes/0.1.5.md`, which
   so far covers only the GPL-3.0 licence change, with the user-visible 0.1.5
   changes. Mac notes go in the same PR.
3. Pins PR: re-check `packaging/release-inputs.json`. If the release needs a
   newer Adwaita tag, Dan approves it first.
4. Version PR: set `package.version` and the runtime notices to 0.1.5.
5. Release candidate: run the Release workflow by hand with version
   `0.1.5-rc1`. Linux checks the AppImage (bwrap sandbox, fresh `HOME`, scan
   `/usr`, Open With LinDirStat). macOS checks the DMG (open, scan, Full Disk
   Access prompt, `xattr` quarantine path). Each posts screenshots and
   results on the PR.
6. **Dan approves the release**, then tags `v0.1.5` from `main`. The tag
   starts the Release workflow.
7. Attach the AppImage, the DMG and their `.sha256` files to the release in
   `danjboyd/LinDirStat-releases`, run `scripts/release-sha256sums.sh v0.1.5`,
   and check the update feed (`docs/updates.md`).

## Intentional differences (not gaps)

Properties panel, POSIX regular expressions in Search, Logical Size off by
default on Linux, custom cleanup paths passed as arguments, and the
Windows-only cleanups. See `docs/windirstat-parity.md`.
