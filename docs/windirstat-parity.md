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
| Directory scan | matched | Background scanner using `fstatat` with a pool of libdispatch workers (Preferences › Advanced, 1–16, default 4), hard links counted once, physical (`st_blocks`) and logical sizes, mtime and mode. WinDirStat's exclusions: mount points (another `st_dev`) and symbolic links are excluded by default (file links skipped, folder links shown as leaves; when followed, folder links are descended with cycle protection and file links count their target), hidden (dot) entries optionally. Filtering page: folder path patterns, file name patterns (glob or POSIX ERE, case-insensitive, anchored) and a minimum file size; an invalid pattern stops the scan with a message. Suspend/Resume and Stop (partial results). Multi-volume scans produce a "This Computer" root. |
| Size semantics | matched | Physical size by default; Treemap › Use Logical Size switches every pane. Directories contribute no bytes of their own. |
| Directory tree pane | matched | WinDirStat's columns: Name, Subtree Percentage, Percentage and the optional Physical Size, Logical Size, Items, Files, Folders, Last Change, Attributes (R and H; the other letters have no Linux meaning) and Owner, chosen in Preferences › Folder List. Sortable headers, multiple selection, symbolic icons, depth-indented percentage bars, dimmed unreadable folders and mount points. Live while scanning: rows appear as directories are read, re-sorted twice a second, with WinDirStat's pacman (or "[N Read Jobs]") on folders still being read and the elapsed time on the root. Different: Logical Size is off by default because two size columns do not fit beside the extension list at GNOME's metrics; depth colours use GNOME's palette in WinDirStat's order and are not configurable. |
| File tabs | matched | All Files, Largest Files (top N by logical size, Preferences › Advanced, live while scanning), Duplicate Files (when "Scan for duplicate files" is on: size buckets, then SHA-512/128 of the first 4 KiB, 1 MiB and whole file, in the background after the scan) Search Results (after a search) and File Watcher (Tools › Start File Watcher). Different: tabs are on top, as GNOME places them. |
| File Watcher | matched | Tools › Start/Stop File Watcher shows or hides the tab, as WinDirStat's toggle does. WinDirStat's columns (Name, Time, Operation, Logical Size; newest first) and verbs (Created, Deleted, Modified, Renamed (Old), Renamed (New)); folder modifications are ignored, as in WinDirStat. `LDFileWatcher` with an inotify backend that watches the scan root (or each drive of "This Computer") recursively on its filesystem, follows renamed folders, watches new ones (listing what they already hold as created), turns moves in and out of the tree into Created and Deleted, and reports queue overflows and the watch limit in the status bar. Batched onto the main thread four times a second; repeated writes to one file collapse into one row per batch. Selecting a row selects the item at that path in the tree. Different: the list keeps the newest 10,000 rows; a new scan empties it and, while the watcher is on, watches the new tree when the scan finishes (WinDirStat stops watching). macOS: FSEvents backend still to come (unsupported until then). |
| Search | matched | Edit › Search… with WinDirStat's options (regular expression, case sensitive, whole phrase; `*` implies whole phrase), names of files only, capped at 10,000 largest. Different: regular expressions are POSIX extended, not ECMAScript. |
| Extension/type pane | matched | Rank-based WinDirStat colours with cushioned swatches, descriptions from shared-mime-info, bytes, % bytes, files, sortable headers; selecting an extension highlights its files in the treemap. Options › Show File Types hides it. |
| Treemap pane | matched | Port of `CTreeMap`, pixel-identical to the oracle. Selection frame, extension highlighting, zoom in/out/reset, Select Parent and Reselect Child, context menu, hover path in the status bar. Preferences › Treemap sets style, grid, brightness, cushion shading, height, scale factor and light source. Options › Show Treemap hides it. Different: no colour pickers for grid and highlight colours (theme colours are used). Show Free Space/Unknown remain. |
| Status/progress | matched | Spinner and live counts while scanning, hovered or selected path, the size of the whole selection ("Physical Size: …"), memory use. |
| Window chrome | matched | GNOME header bar with Select Target, Refresh, Suspend/Resume, Stop, Search, Move to Trash, Select Parent, Zoom Out, Zoom In; the primary menu has File, Edit, Clean Up, Treemap and Options. Drawn entirely by the Adwaita GNUstep theme, light or dark. |
| Folder/drive selection | matched | Select Target offers all local drives, individual drives (with total, free and a usage bar from `statvfs`; pseudo, network and FUSE filesystems left out) or a folder with a history, plus the duplicates option. |
| CSV | matched | File › Save/Load Results To CSV and Save Duplicates To CSV in WinDirStat's formats; WinDirStat's own CSVs load too. Different: embedded quotes are doubled; Index is always 0 (inode numbers are not kept). |
| Preferences | matched | WinDirStat's Options pages as a GNOME Preferences window: General, Filtering, Folder List, Treemap, Cleanups, Prompts, Advanced. Windows-only settings are left out; dark mode follows GNOME's style instead of an app setting. |

## File Actions

| Area | Status | Notes |
| --- | --- | --- |
| Open | matched | `xdg-open` (`open` on macOS) for each selected item; Enter. |
| Open With | matched | WinDirStat's "Windows Explorer Menu" submenu, at the end of the Clean Up and file list menus: the applications that open every selected item, the default first. `LDOpenWith`: desktop entries from `$XDG_DATA_HOME` and `$XDG_DATA_DIRS`, the user's and system's `mimeapps.list` (desktop-specific lists first; default, added and removed associations), shared-mime-info aliases and subclasses (a C file also offers text editors); started through the `Exec` line with `%f %F %u %U %i %c %k` expanded and exact path bytes, in a terminal for `Terminal=true`. macOS: NSWorkspace backend still to come (empty until then). |
| Show in Files | matched | `org.freedesktop.FileManager1.ShowItems` over D-Bus (gdbus or dbus-send), falling back to opening the containing folder. WinDirStat's "Select in Explorer". |
| Open Terminal Here | matched | WinDirStat's Command Prompt/PowerShell Here: `$TERMINAL`, GNOME Console, GNOME Terminal, Ptyxis, Konsole, Xfce Terminal, `x-terminal-emulator` or xterm, in each selected folder (a file's parent). |
| Properties | different | An in-app panel (path, type, sizes, contents, permissions, owner, group, links, inode, times) instead of the shell's dialog. |
| Copy Path | matched | Every selected path, one per line. |
| Move to trash | matched | freedesktop.org Trash 1.0: the home trash, or `$topdir/.Trash/$uid` / `$topdir/.Trash-$uid` on other filesystems; never copies across filesystems, never overwrites. Del. |
| Delete permanently | matched | Shift+Del; never follows symbolic links or enters other filesystems; reports what it could not remove. |
| Delete warning | matched | WinDirStat's warning lists every path, defaults to Cancel and has "Do not show this message again" (Preferences › Prompts restores it). |
| Empty Folder, Move To, Empty Trash | matched | Empty Folder deletes a folder's contents permanently; Move To renames, or uses `mv` across filesystems, never replacing; Empty Trash empties the home and per-volume trashes. |
| Refresh | matched | After any change on disk the affected items are rescanned in place or removed, totals and order updated upward, with selection and zoom kept (WinDirStat's refresh engine); a trash folder inside the tree is refreshed after trashing. Refresh Selected (F5), Refresh All (Shift+F5). |
| Custom cleanups | matched | Ten slots (Ctrl+0–9) with WinDirStat's fields and rules: `/bin/sh -c`, `%p`, `%n`, `%sp`, `%sn`, works-for kinds, recursion (children first), confirmation, run in a terminal, wait, refresh policy. Different: WinDirStat pastes paths unquoted; Linux names can contain quotes and `$(…)`, so placeholders become shell parameters with the exact paths passed as arguments. |
| Compute Hash | matched | MD5, SHA-1, SHA-256, SHA-384 and SHA-512 of one file. |
| Windows-only cleanups | different | Compression, sparse files, hibernation, Disk Cleanup, and shadow copies have no Linux equivalent and are left out; the Explorer menu is Open With. |

## Platform And Packaging

| Area | Status | Notes |
| --- | --- | --- |
| Linux GNUstep build | partial | Builds through `gnustep-cli-new`. |
| Linux Adwaita default | partial | Manifest declares Adwaita as packaged default with `ifUnset`; full packaged theme payload validation remains. |
| Linux AppImage | partial | `gnustep-packager` manifest/build/stage/validate path exists. Full AppImage packaging is currently blocked by packager handling of apps with no MIME/file associations. |
| macOS app | partial | Builds and runs natively against Apple's AppKit, with the test suite passing on macOS; see `docs/macos.md`. |
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

The gate renders each fixture in `Tests/Fixtures/windirstat-parity/trees.json` at three viewport sizes with the production renderer (`Tools/windirstat-parity-exporter --ppm`, which calls `LDTreemap` and the rank-based palette) and with an independent Python port of WinDirStat's `CTreeMap` (`references/WinDirStat/windirstat/Controls/TreeMap.cpp`). It is strict by default: any leaf rectangle difference, any channel drift above 2, or under 99.9% exact pixels fails. Current status: all fixtures match exactly.

Output is written to `dist/validation/windirstat-parity`, including both images, a diff image, rectangle JSON and `summary.json`.

For full-window review, run:

```sh
./scripts/gui-parity-correlation.sh
```
