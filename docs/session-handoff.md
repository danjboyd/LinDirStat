# Session Handoff

Last updated: 2026-10-09

## Current State

Audit steps A (scan), B (treemap), C (window chrome) and D (cleanup and
WinDirStat's remaining workflow) are done. `docs/windirstat-parity.md` has
the detail; `docs/windirstat-step-d-reference.md` is the behavioural
reference taken from the WinDirStat source for step D.

Step C:

- The tree is shown while scanning. Each directory's children are published once as a complete array (`-[LDDirectoryNode publishChildren:]`), totals grow by atomic upward adds, and the arrays replaced by the final sort are released on the main thread. Pending-read counts drive WinDirStat's pacman (or "[N Read Jobs]") in the Subtree Percentage column; the root's Percentage shows the elapsed time.
- Optional columns (Physical/Logical Size, Items, Files, Folders, Last Change, Attributes, Owner) are chosen in Preferences › Folder List.

Step D:

- Clean Up menu and context menus with WinDirStat's enablement table (`LDCommandRules`): Open, Show in Files, Open Terminal Here, Copy Path, Refresh Selected, Properties, Move to Trash, Delete Permanently, Empty Trash, Empty Folder, Move To, ten custom cleanups (`LDCustomCleanupRunner`).
- `LDFileOperations`: freedesktop.org trash, permanent delete that never follows symlinks or crosses filesystems, move that never replaces. `LDDesktop` launches with byte-exact arguments.
- Refresh engine (`AppController+Cleanup.m`): after any change on disk the affected entries are rescanned (`-[LDScanner scanEntryAtPathData:]`) or removed, and totals and order are updated upward. Detached subtrees are kept until the next scan because parent pointers do not retain.
- File tabs (`AppController+FileLists.m`): Largest Files, Duplicate Files (`LDDuplicateFinder`), Search Results (`LDSearch`). Also CSV save/load (`LDCSV`), Compute Hash (`LDHasher`, nettle), filters and exclusions (`LDScanOptions`), suspend/resume, "This Computer" multi-volume scans (`LDComputerNode`), volumes (`LDVolumes`), the Select Target dialog, the Preferences window (`LDOptionsWindowController`) backed by `LDPreferences`, and Options › Show File Types/Show Treemap.
- Dark mode follows GNOME's style through the theme; checked on a private display.
- Options › Show Free Space / Show Unknown (F6/F7): `<Free Space>` and `<Unknown>` are leaf nodes of kind `LDFileNodeKindFreeSpace`/`LDFileNodeKindUnknown` (`-isSpaceItem`) under each volume root, maintained by `LDSpaceItems` after every scan, refresh and toggle (`-[AppController updateSpaceItems]`). Disk usage comes from `+[LDVolumes getTotalBytes:freeBytes:forPathData:]` and `+isVolumeRootPathData:` (portable `statvfs`/`stat`). `LDTreemap` honours WinDirStat's `COLORFLAG_DARKER/LIGHTER` (`LDRGBColorFlag…`).

macOS: LinDirStat also builds natively against Apple's AppKit (`make -C macos`); platform differences live in small modules. See `docs/macos.md`.

## Verify

```sh
./scripts/run-tests.sh
./scripts/windirstat-parity-gate.sh
make -C Source && LINDIRSTAT_SCAN_PATH=/usr/share/doc openapp Source/LinDirStat.app
```

Run GUI checks on a private display (`docs/development.md`, "GUI review on a private display").

## Where To Resume

The remaining parity work is split between the Linux and macOS sessions in `docs/parity-plan.md`.


- Treemap colour pickers (grid and highlight colours) and the treemap preview in Preferences.
- A `.desktop` file action ("Open with LinDirStat") in place of WinDirStat's Explorer menu entry.
- Full-window parity gate (roadmap 12J).

## Known Gaps and Theme Notes

- Theme/libs-gui issues reported to the Adwaita theme session rather than worked around: NSSplitView gives half-pixel frames with thin dividers; `-[NSTableView setColumnAutoresizingStyle:]` is not implemented, so GNUstep resizes a table's last column (the app keeps it at its natural width while fitting its flexible column); NSAlert has no accessory view or suppression button (the delete warning is a custom panel of standard controls); disabled pop-up buttons do not look disabled; pop-up buttons size too narrow for the theme's arrow; NSTabView does not scroll tabs that do not fit.
- Refreshing a subtree counts hard links inside it again if their other links are outside it (the hard-link set covers one scan).
- CSV Index is always 0 (inode numbers are not kept).
- Show in Files is allowed on scan roots and mount points (WinDirStat allows folders and files only); on Linux the file manager handles them fine.
- Adwaita theme #66/#67 (pop-up width, combo list padding) verified with theme main 8f75da8; the unit pop-up no longer needs a minimum width.
