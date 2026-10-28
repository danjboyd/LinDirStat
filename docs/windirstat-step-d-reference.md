# WinDirStat behavioural reference for Step D

Source: `references/WinDirStat/windirstat/` (C++/MFC). This file records the behaviour a GNUstep/AppKit port must reproduce; MFC plumbing is left out. Citations are `file:line` into WinDirStat `release/v2.9.3` (`40d77b69`), the pinned submodule revision, using these abbreviations. A citation prefixed `7da9c724:` points at the previous pin (`7da9c7247a1df11687da63a08d7a2edbea8b4561`), with the full file name, and marks behaviour this file documents that v2.9.3 no longer has in that form.

| Abbrev | File |
|---|---|
| `RC` | `windirstat.rc` |
| `WM` | `WinDirStatModel.cpp` |
| `WMA` | `WinDirStatModel.Actions.cpp` |
| `MF` | `MainFrame.cpp` |
| `MC` | `MainFrame.Commands.cpp` |
| `OPT` | `Options.h` (settings and defaults) |
| `OPTC` | `Options.cpp` |
| `EN` | `res/langs/lang_en.txt` (English strings) |
| `IX` | `Item.Extended.cpp` |

*Windows-only* marks features with no Linux meaning. Each one gets a suggested Linux equivalent or *omit*.

---

## 0. Enablement model (applies to every selection command)

All selection-dependent commands go through one table (`WMA:26-168`). Each command declares:

- **none**: allowed with nothing selected. · **many**: allowed with more than one item selected. · **early**: allowed while a scan runs. Otherwise it needs `IsRootDone() && !IsScanRunning()`. · **focus**: only the treemap commands use this, and they require the file tree. · **types**: every selected item must be one of these types. Reserved system files block anything not typed "any". · **extra**: an additional predicate.

"Selection" means the selected rows of the list with logical focus: file tree, Largest, Duplicates or Search. A duplicate group node expands to its children (`WM:901-936`). Item types are listed at `Item.h:33-75`.

| Command | none | many | early | types | extra | Cite |
|---|---|---|---|---|---|---|
| Open Item | n | y | **y** | Computer/Drive/Dir/File | | WMA:106 |
| Properties | n | y | **y** | Computer/Drive/Dir/File | | WMA:107 |
| Copy Path | n | y | **y** | Drive/Dir/File | | WMA:121 |
| Select in Explorer | n | y | **y** | Dir/File | | WMA:102 |
| Cmd / PowerShell here | n | y | **y** | Drive/Dir/File | | WMA:104-105 |
| Refresh Selected | n | y | n | Computer/Drive/Dir/File | | WMA:126 |
| Refresh All | y | y | n | any | | WMA:125 |
| Delete (to Bin) | n | y | n | Dir/File | not root and on a local drive | WMA:91 |
| Delete Permanently | n | y | n | Dir/File | not root | WMA:90 |
| Empty Folder | y¹ | y | n | Dir | not root | WMA:100 |
| Move to… | n | y | n | Dir/File | not root | WMA:94 |
| Compute Hash | n | **n** | y | File | | WMA:120 |
| Compress (each algorithm) | n | y | n | Dir/File | volume supports the algorithm | WMA:114-119, 170-184 |
| Sparsify | n | y | n | File | | WMA:111 |
| Save Results | y | y | n | any | | WMA:129 |
| Save Duplicates | y | y | n | any | Duplicates tab visible | WMA:127 |
| Search… | y | y | n | any | | WMA:133 |
| Suspend | y | y | y | any | root exists, not done, not suspended | WMA:132 |
| Resume | y | y | y | any | suspended | WMA:130 |
| Stop | y | y | y | any | root exists, not done | WMA:131 |
| Zoom In | n | n | n | Drive/Dir/File | not root; not a direct child of the zoom item | 7da9c724:DirStatDoc.cpp:953 |
| Zoom Out | y | y | n | any | zoom item ≠ root | WMA:139 |
| Zoom Reset | y | y | n | any | zoomed | WMA:137 |
| Select Parent | n | n | y | any | has a parent | 7da9c724:DirStatDoc.cpp:951 |
| Reselect Child | y | y | y | any | reselect stack not empty | 7da9c724:DirStatDoc.cpp:950 |
| Show Free Space / Unknown | y | y | n | any | | WMA:140-141 |

*Later upstream (v2.5.7):* Zoom In also requires the target (the item, or a file's parent) to have a treemap size above 0 (`cc74efab`). Treemap hit testing stops at an item of size 0 (`86abc10a`). LinDirStat's layout never subdivides such an item, so its hit test already stopped there.
Add to Exclusion Filter (v2.5.8, `a874bcf4`, `c9501507`) is `n | y | n | Drive/Dir/File`; LinDirStat leaves out scan roots and mount points (§9).

¹ Empty Folder is listed as allowing an empty selection, but the extra predicate is evaluated against `nullptr` and fails, so in practice it needs a selection.

**Port rule:** while a scan runs, every destructive action and every refresh is disabled. Open, Properties, Copy Path, Reveal and Terminal stay enabled.

---

## 1. Clean Up menu, context menus and cleanup commands

### 1.1 Clean Up menu, in order (`RC:121-170`; labels `7da9c724:res/langs/lang_en.txt:76-141`; accelerators `RC:359-416`)

1. &Open... (Enter) · 2. — · 3. Select in &Explorer... (Ctrl+E) · 4. Open in C&ommand Prompt... (Ctrl+P) · 5. Open in Power&Shell... (Ctrl+S) · 6. &Properties (Alt+Enter) · 7. — · 8. Delete Permanently (Shift+Del) · 9. &Delete (to Recycle Bin) (Del) · 10. Empty Recycle &Bin. The label gets an async suffix, " (N Items, X)" (`MC:77-110`, `EN:191,328`). · 11. Empty Folder · 12. &Move to... (Ctrl+M) · 13. — · 14. Compress ▸: No compression, —, LZNT1, XPRESS4K, XPRESS8K, XPRESS16K, LZX. The submenu is greyed when no child is enabled (`MC:156-171`). *Windows-only.* · 15. Sparsify File; Optimize VHD Files; Deduplicate with &Hardlink; Remove Mark-Of-The-Web Tags. *Windows-only.* · 16. — · 17. Disable Hibernate File; Run Windows Disk Cleanup Utility; Launch Program && Features; Remove Cached Roaming Profiles; Remove Local Profiles; Remove Volume Shadow Copies (with a count/size suffix); Component Store Cleanup ▸ (three DISM verbs). *All Windows-only; omit.* · 18. — · 19. Custom Cleanup ▸, rebuilt every time the menu opens (§1.6).

### 1.2 File tree context menu (`RC:269-316`, built at `Controls/TreeListControl.cpp:814-880`)

1. Expand/Collapse. This is the bold default item. On a row with no children, the item and its separator are removed and Open becomes the default (`TreeListControl.cpp:837-848`). · 2. — · 3. Open... · 4. — · 5. Copy Path · 6. Select in Explorer... · 7. Open in Command Prompt... · 8. Open in PowerShell... · 9. Refresh Selected · 10. Properties · 11. Compute Hash · 12. — · 13. Delete Permanently · 14. Delete (to Recycle Bin) · 15. Empty Folder · 16. Move to... · 17. — · 18. Compress ▸ · 19. Sparsify File · 20. Optimize VHD Files · 21. — · 22. Custom Cleanup ▸ · 23. — · 24. Windows Explorer Menu ▸: the native shell menu, filled lazily (`MC:34-61`). *Linux: omit, or "Open With…".*

The Largest, Duplicates and Search lists are the same tree-list class and show this same popup. Enablement follows §0.

### 1.3 Treemap context menu (`RC:318-351`)

1. Zoom In · 2. Zoom Out · 3. Zoom Reset · 4. Reselect Child · 5. Select Parent · 6. — · 7. Copy Path · 8. Select in Explorer · 9. Open in Command Prompt · 10. Open in PowerShell · 11. — · 12. C&ancel
*Later upstream (v2.5.8+):* Add to Exclusion Filter follows Open in PowerShell. The file tree context menu has it after Compute Hash (`a874bcf4`; §9).

### 1.4 Command semantics

*Later upstream (v2.7, `262a1b94`, `489323a5`; v2.9.0 `WinDirStatModel.Actions.cpp`):*
- **Clean Up › Remove Empty Folders** (also in the tree's context menu, between Delete to Recycle Bin and Empty Folder): available for drives and folders, several at a time, not while scanning. It collects every folder in the selection whose subtree holds no files (`GetFilesCount() == 0`), never the root, never entering reparse points. It confirms once, listing them (`ShowRemoveEmptyFoldersPrompt`), then removes them deepest first with `RemoveDirectory` and refreshes the parents left standing.
- **Tools › Change Folder Dates to Last Change** (`ShowSetDatesPrompt`): every folder in the selection (or the whole tree when nothing is selected) gets its Last Change, the newest time below it, as its modification time.
- **LinDirStat:** both commands never go through a symlink (checked on disk) and skip mount points and unreadable folders, whose contents the tree does not show. Folders are removed with `rmdir(2)`, which cannot remove anything that is not empty: a folder holding filtered-out or hidden entries fails and is reported. Dates are set with `utimensat` on the folder itself, leaving its access time.
- **On macOS** neither command enters a package (an app, a bundle, a Photos or Final Cut library: `NSURLIsPackageKey`) unless that package is itself selected. Such packages keep intentionally empty folders, and their layout is part of what makes them work. Finder leaves `.DS_Store` files in folders it has shown, so most folders that look empty there are not empty on disk, and they are kept. A folder counts as empty only when every child is an empty folder that is listed too, so one holding a skipped package, a link, a mount point or a folder the scan could not read is kept (upstream would list it, and its `RemoveDirectory` would fail). The folder's entries on disk must also be exactly those children, so one holding what the tree leaves out (symbolic links to files with Exclude Symbolic Links on, hidden files with Exclude Hidden, entries the filters drop) or anything new since the scan is kept too.

**Open (`WMA:795-801`, `WM:353-387`)**
Runs the default shell verb on each selected item. For MyComputer it opens "This PC". Reserved items are skipped. *Linux:* `NSWorkspace openFile:` once per item.

**Properties (`7da9c724:DirStatDoc.cpp:1613-1619`)**
Runs the shell "properties" verb on each item. *Linux:* an in-app info panel with path, kind, sizes, mtime, mode, owner and nlink.

**Copy Path (`WMA:296-307`)**
Copies the full paths of all selected items, joined with `\r\n`. Use `\n` on Linux.

**Select in Explorer (`WMA:449-490`)**
Groups the items by parent directory and opens one file-manager window per parent, with those children selected. *Linux:* D-Bus `org.freedesktop.FileManager1.ShowItems`, or `NSWorkspace selectFile:inFileViewerRootedAtPath:`.

**Command Prompt Here (`WMA:492-513`)**
Takes the unique folders of the selection: the item itself for a directory, its parent for a file. Opens one console per folder, titled `WinDirStat - "<path>"`.

**PowerShell Here (`WMA:515-542`)**
Same as Command Prompt Here, using `pwsh.exe` and falling back to `powershell.exe`. *Linux:* merge both into one "Open Terminal Here" (`$TERMINAL` or `x-terminal-emulator`, with cwd set to the folder).

**Delete Permanently / Delete to Bin / Empty Folder: `DeletePhysicalItems(items, toTrash, emptyOnly)` (`WM:488-648`)**
1. **Warning.** Shown when `ShowDeleteWarning` is on (default true, `7da9c724:Options.cpp:60`). A Yes/No dialog titled "Warning", with text `IDS_DELETE_WARNING` or, for Empty Folder, `IDS_EMPTY_FOLDER_WARNING` (`EN:56,69`). It lists every path in a scrollable list (600×400). It has a "Do not show this message again." checkbox. Yes with the box ticked turns the warning off (`7da9c724:DirStatDoc.cpp:445-462`). Trash shows the same prompt.
2. **Selection.** Cleared, except for Empty Folder (`WM:512-517`).
3. **Empty Folder targets.** The *children* of each selected folder are deleted, permanently (`WM:519-525`, `WMA:554-557`).
4. **Permanent delete** (`WM:534-596`), under a cancellable progress dialog sized to the item count: Walk depth-first without following reparse points. Delete the files in parallel, force-clearing read-only first. Remove the directories deepest-first. Any top-level item that still exists falls through to the shell delete in step 5.
5. **Trash** (`WM:598-627`): one shell operation with the recycle and undo flags. The native progress UI shows only when `ShowMicrosoftProgress` is on (default off). *Linux:* `NSWorkspace recycleURLs:` or freedesktop trash.
6. **Tree update** (`WM:629-647`): no ad-hoc node removal. The command calls `RefreshItem(items + the drive's recycler folders when trashing)`, which is `StartScanningEngine(items)`. Because the deleted paths are gone, that refresh removes their nodes and subtracts their sizes from every ancestor (next block).

**Refresh / rescan engine: `StartScanningEngine(items)` (`WMA:993-1346`)**
1. **Prepare.** Stop any running scan. If an item is an ancestor of the zoom item, zoom to that item. Clear the reselect stack. Suspend treemap drawing (`WMA:995-1037`). If the single item is MyComputer, use its drive children instead (`WMA:1049-1054`).
2. **Prune each item** (`7da9c724:DirStatDoc.cpp:1805-1862`): Drop its files from the Duplicates, Largest and Search lists. Remember expansion, scroll position and selection. If it was done, call `UpwardSubtract{SizePhysical,SizeLogical,Files,Folders}` (and extension stats), **remove all its children**, mark the item and its ancestors undone, and re-expand it. If its path no longer exists: the root unlinks to an empty document; anything else is removed from its parent, and the parent's file/folder count is decremented.
3. **Rescan** (`7da9c724:DirStatDoc.cpp:1867-1902`). On a worker thread, each remaining item gets one read job and goes onto a per-volume queue served by `ScanningThreads` threads. A refreshed *file* simply re-stats (`Item.cpp:1181-1188`).
4. **Finish** (`7da9c724:DirStatDoc.cpp:1911-2014`): re-create `<Free Space>`/`<Unknown>` if enabled; rebuild the hardlink items; finalize (sort, extension data); restore the treemap and extension panes; restore scroll and selection.

**Refresh Selected (F5; `WMA:232-238`)**
When the only selected item is the root, behaves as Refresh All. Otherwise the subtree is pruned and rescanned in place.

**Refresh All (Shift+F5; `WMA:240-243`)**
Re-opens the same path spec, giving a brand-new root.

**Move to… (`WMA:559-620`)**
Shows a folder picker, then runs one shell move. Afterwards it refreshes each unique parent of the moved items, plus the destination folder if it is inside the tree.

**Empty Recycle Bin (`7da9c724:DirStatDoc.cpp:1155-1175`)**
Empties all bins with no confirmation, then rescans each drive's recycler folder. *Linux:* empty `~/.local/share/Trash` and `$mnt/.Trash-$uid`, then refresh any of those folders that are in the tree.

**Compute Hash (Ctrl+H; `WMA:824-843`, `7da9c724:HelpersTasks.cpp:667-671`)**
Works on exactly one file. Shows a message box with MD5, SHA1, SHA256, SHA384 and SHA512.

**Show Free Space / Show Unknown (F6/F7; `WMA:347-415`)**
- Toggles the `<Free Space>` and `<Unknown>` pseudo-files under each drive (`EN:78,347`). · Persisted as `ShowFreeSpace` and `ShowUnknown`, both default false (`OPT:230,236`). · The toggle then recalculates via `StartScanningEngine({})`.

### 1.5 Prompts that gate cleanup (Prompts page, §10)

- Delete warning (above). · Custom-cleanup confirmation (§1.6). · Cloud-link warning: once per scan during duplicate detection (`Controls/FileDupeControl.cpp:24-38`). · Elevation prompt: *Windows-only*.

### 1.6 User-defined cleanups ("Custom Cleanup"; `Options.h:88-142`, `Pages/PageCleanups.cpp`, `WM:699-831`)

**Slots.** There are 10, numbered 0–9. Slot *i* has the shortcut **Ctrl+*i*** (`7da9c724:windirstat.rc:396-405`), and its menu text is `"<Title>\tCtrl+<i>"` (`7da9c724:res/langs/lang_en.txt:265`).

**Fields** (all default empty, false or 0; `Options.h:91-105`):

| Field | Notes |
|---|---|
| Title | Shown as `Custom Cleanup #i` while the title is "virgin" (`OPTC:192-199`) |
| CommandLine | |
| Enable | |
| WorksForDrives | |
| WorksForDirectories | |
| WorksForFiles | |
| WorksForUncPaths | |
| RecurseIntoSubdirectories | |
| AskForConfirmation | |
| ShowConsoleWindow | |
| WaitForCompletion | |
| RefreshPolicy | 0 = "No refresh", 1 = "Refresh this entry", 2 = "Refresh this entry's parent" (`EN:292-294`) |

**Page layout (`7da9c724:windirstat.rc:452-484`)**
- A listbox of the 10 titles, with Up and Down buttons. · Enabled, Title, Command Line, and the placeholder hints. · A "Works for" group: Drives, UNC Paths, Files, Folders. · Recurse into Subdirectories, Ask for Confirmation, Show Console Window, Wait for Completion. · Refresh Policy combo.

**Page rules (`PageCleanups.cpp:94-127`)**
- Every control is disabled unless Enabled is ticked. · Recurse is enabled only when Drives or Folders is ticked; otherwise it is forced off. · Recurse forces Wait on and disables the Wait checkbox. · Wait off forces the policy to No refresh. · The `%sp`/`%sn` hints are visible only when Recurse is on. · An empty title resets to the default title (`:51-66`).

**Placeholders (`WM:810-831`)**

| Placeholder | Meaning |
|---|---|
| `%p` | full path of the item |
| `%n` | its base name |
| `%sp` | current subdirectory path (recursive mode) |
| `%sn` | current subdirectory name (recursive mode) |

Substitution goes through `>`-markers so a `%` inside a filename is safe. Paths are **not** auto-quoted.

**Menu enablement (`WM:343-351`, `WMA:720-732`, `MC:173-211`)**
- The slot is enabled, the selection is non-empty, and the file tree has focus. The update handler also accepts the Duplicates and Largest lists. · **Every** selected item matches a ticked type: drive, dir, file or UNC. · The submenu is greyed when no slot is enabled.

**Execution, per selected item (`WMA:734-772`)**
1. **Confirm.** When asked for, show a Yes/No box: "You are about to call a [Recursive] Custom Cleanup '<title>' on '<path>'. Continue?" (`7da9c724:res/langs/lang_en.txt:238,264`). No skips that item. · 2. **Check the path.** A missing path shows an error and skips the item (`WM:699-735`). · 3. **Run** `%COMSPEC% /C <cmd>` with cwd set to the directory (for a file, its parent). The console is hidden unless ShowConsoleWindow is ticked. If Wait is on, wait (`WM:780-808`). · 4. **Recursive mode** (`WM:764-778`): post-order depth-first over the subdirectories, following only allowed reparse points. The command runs in each one and always waits. · 5. **Refresh.** Queued items get the refresh policy (entry, or parent; parent falls back to the item if it is the root). This only happens if Wait was on (`WM:737-762`).

*Linux:* use `/bin/sh -c`. "Show console" becomes "run in terminal". "UNC" becomes network mounts, or is dropped.

---

## 2. Scan-time tree, Pacman and progress

**The tree is live during the scan.**
- `OnOpenDocument` creates the root, sends `HINT_NEWROOT` so the root row appears at once, then starts the engine (`WM:78-158`). · Children are inserted as they are discovered: `AddChild` on a visible, expanded parent marshals `OnChildAdded` to the UI thread (`7da9c724:Item.cpp:136-142`). · **The treemap and extension list are collapsed during the scan.** Their splitter is set to 1.0 and treemap drawing is suspended (`WM:81`, `WMA:1037`, `MF:696-716`). · After the scan they are restored: treemap at 0.5, extension pane at 0.72 (`7da9c724:MainFrame.cpp:806-826`, `7da9c724:DirStatDoc.cpp:1995-2001`).

**UI timer: 25 ms (`MF:531`, `7da9c724:MainFrame.cpp:840-878`)**
- While scanning and not suspended, every tick: updates the progress display; calls `FileTree SortItems()`, which re-sorts and repaints rows and so advances the pacmen.
- Every 15th tick (~375 ms): re-sorts the Duplicates tab, if it is active; re-sorts the Largest tab, if it is active; refreshes the status text and RAM display.

**Per-row Pacman, in the Subtree Percentage column (`IX:49-167`)**
- **Read-job mode.** A row is in read-job mode while its *parent* is not done; the root uses its own done state (`MustShowReadJobs`, `IX:1132-1140`).
- **Cell content.** Read-job mode, PacmanAnimation on (default true, `OPT:191`), item not done: an animated pacman. Read-job mode otherwise: the text `[1 Read Job]` or `[N Read Jobs]` (`IX:199-209`, `EN:192,335`). Out of read-job mode: the percentage bar, indented by level (`7da9c724:Item.Extended.cpp:65-70`). In read-job mode the column sorts by read-job count (`7da9c724:Item.Extended.cpp:210-219`).
  - *Later upstream (v2.6, `5be7353c`; sorting fixed in `304b682a`):* the column is renamed **Size Proportion**. Over a light track the bar draws the share of the parent in a blend of the track and the level's colour, and inside it, inset, the share of the whole scan in the full colour. The indent is the level times `SizeProportionIndent` (default 16, settings file only). Hovering the bar shows "Size proportion of total scan: N%" and "…of parent folder: N%" (`IDS_SIZE_PROPORTION_TOOLTIPss`). The colours page is renamed Size Proportion Color. LinDirStat follows this: its bar is the share of the parent at 45% of the level's colour with the share of the scan inset in full colour, and `SizeProportionIndent` is clamped to 0–1000 points (and never pushes the bar out of its column). libs-gui does not ask for cell tooltips, so `LDOutlineView` adds a tooltip rect per visible row and asks for the text of the row under the pointer. The column already sorted by the treemap's size, so `304b682a` needs nothing. Upstream's later `98f6dd98` (tooltip font after a font-size change) has no counterpart.
- **Percentage column.** Shows `[elapsed]` when `ShowTimeSpent` is on (default true, `OPT:232`) and the row is in read-job mode. The **root row always** shows `[elapsed]`. Otherwise it shows `NN.N%` (`IX:211-217`).
  - *Later upstream (v2.6, `db7af300`):* `UseAbsolutePercentages` (default **true**, toggled by View › Show Absolute Percentages) makes the column show each row's share of the whole scan (`CItem::GetAbsoluteFraction`: size over the topmost ancestor's size, by the logical/physical choice). With it on, the root shows `100.0%` instead of `[elapsed]`; with it off the column is as above. Sorting is unchanged, because siblings rank the same either way. The Size Proportion bar keeps share-of-parent as its outer layer. LinDirStat follows this, with the toggle in its Treemap menu.
  - *Later upstream (v2.6, `e451d346`):* the per-folder `[elapsed]` times use a scan clock that stops while the scan is suspended (`CItem::GetScanTickCount`), so paused time no longer counts. LinDirStat's root already excluded it. Its folders now do too (`LDScanClockActiveMilliseconds`), and stopping a suspended scan restarts the clock.
- **Driving the pacmen.** Each entry a scanner thread adds walks up its ancestors. An ancestor with 0 read jobs stops its pacman; the others advance (`IX:718-731`, `7da9c724:Item.cpp:936-958`).
- **Animation** (`Controls/PacMan.cpp:10-128`): It moves 0.09 px/ms, bouncing between the cell edges. The mouth changes 0.003/ms, opening to at most 90°. Fill `#FCC92F` with a black outline. After more than 750 ms with no update it stops and draws three "z"s (`#888888` in dark mode). The global suspend flag freezes it.

**Status-bar progress (`MF:302-324`, `MF:370-458`, `IX:533-571`)**
- **Range.** For a drive or MyComputer root, the range is the used bytes, total − free. · **Range forced to 0** for a folder root, **or** when any of ExcludeVolumeMountPoints, ExcludeJunctions or ExcludeSymbolicLinksDirectory is off (the traversal can leave the volume). · **Range > 0:** a progress bar in status pane 0; position = drive size − free-space item, capped at 100%; window title prefixed `"NN% "`, with `(Suspended)` appended when suspended. · **Range = 0:** a pacman in status pane 0; title prefixed `"Scanning "` (plus `(Suspended)`; `EN:320,340`). · **Completion** (`MF:334-349`): clear the prefix, remove the widget, and do a final sort of the tree, Duplicates and Largest lists.

**Suspend / Resume / Stop**
- **Suspend** (Ctrl+Alt+Space): every per-volume queue blocks workers in `WaitIfSuspended`, the pacmen freeze, and the taskbar shows paused (`WMA:903-915`, `MF:351-368`). · **Resume** (Ctrl+Alt+R): `WMA:917-927`. · **Stop** (Ctrl+Alt+T): cancels the queues and keeps the partial tree (`WMA:929-961`).

**Status bar panes (`UiPanes.h:502`, `MC:330-392`)**
- **Pane 0:** "Ready" (`EN:91`). It also hosts the progress widget. Treemap hover shows the hovered path (and its size in pane 1). After the scan, one selected item shows its full path. With the extension list focused it shows `*.<ext>`. · **Pane 1:** `Physical Size: ∑ <sum of selected>`. · **Pane 2:** process RAM.
- *Later upstream (v2.6, `9e134e2d`):* with several items selected, pane 0 shows `N Items Selected | N Files | N Folders`. Each selected file or folder counts itself, plus the files and folders below it. LinDirStat counts an item inside another selected one only once; upstream counts it twice.

---

## 3. File tree columns (`7da9c724:Item.h:29-43`, `7da9c724:Views/FileTreeView.cpp:27-53`)

| # | Column | Align | Width | Optional? | Default | Setting |
|---|---|---|---|---|---|---|
| 0 | Name | L | 250 | fixed | – | – |
| 1 | Subtree Percentage | R | bar+30 | fixed | – | – |
| 2 | Percentage | R | 90 | fixed | – | – |
| 3 | Physical Size | R | 90 | opt | **on** | ShowColumnSizePhysical (`7da9c724:Options.cpp:59`) |
| 4 | Logical Size | R | 90 | opt | **on** | ShowColumnSizeLogical (`7da9c724:Options.cpp:58`) |
| 5 | Items | R | 90 | opt | off | ShowColumnItems (`7da9c724:Options.cpp:55`) |
| 6 | Files | R | 90 | opt | **on** | ShowColumnFiles (`7da9c724:Options.cpp:53`) |
| 7 | Folders | R | 90 | opt | off | ShowColumnFolders (`7da9c724:Options.cpp:54`) |
| 8 | Last Change | L | 120 | opt | **on** | ShowColumnLastChange (`7da9c724:Options.cpp:56`) |
| 9 | Attributes | L | 90 | opt | off | ShowColumnAttributes (`7da9c724:Options.cpp:52`) |
| 10 | Owner | L | 200 | opt | off | ShowColumnOwner (`7da9c724:Options.cpp:57`) |

**Toggling columns**
- The **only** toggle is Options › Folder List › "Optional Columns" (`7da9c724:windirstat.rc:486-512`). There is **no header context menu**.
- On OK, if anything changed, `CreateColumns()` runs (`7da9c724:Pages/PageFileTree.cpp:112-145`, `7da9c724:Views/FileTreeView.cpp:37-52`): 1. reset the sort to Percentage, descending; 2. delete all optional columns; 3. re-add the enabled ones in the fixed order above.
- *Later upstream (v2.6, `db7af300`; `ab1eaa36`, `7efbe418`):* a right click on any list's header shows a column chooser (`Controls/WdsListControl.cpp:923-968`). It lists every column in insertion order, checked when shown. Required columns are greyed out: the first column always, and Size Proportion in the file tree (`Views/FileTreeView.cpp:27-29`). Choosing an item toggles the column (`SetColumnVisible`, `:758-787`). A hidden column keeps its slot at zero width, so it comes back where it was. If the list was sorted by it, the list sorts by the first column with that column's default direction; a hidden secondary sort column is dropped. At creation a list sorted by a hidden column also falls back to the first column (`OnColumnsInserted`, `:268-322`). Visibility is a per-list `ColumnVisibility` setting (file tree, extensions, drives, Largest Files, Duplicates, Search, File Watcher, Permissions), and every column starts shown except the file tree's defaults (`Options.cpp:149-152`). The eight `ShowColumn*` settings are gone. **Percentage becomes optional** (default on), and Options › Folder List gains a Percentage checkbox; that page and the header menu edit the same setting. The default sort moves to Size Proportion, descending. Save Results includes Owner when the file tree shows it. LinDirStat follows this with `LDColumnChooser` on the folder tree, extension list, Select Target drive list, Largest Files, Duplicates, Search Results and File Watcher (it has no Permissions view). Differences: LinDirStat keeps its `ShowColumn*` keys (plus `ShowColumnPercentage`) as the folder list's setting, so existing preferences carry over, and the other lists keep their hidden columns in `HiddenColumns` (`{list: [column, ...]}`). A hidden column is removed from the table rather than given zero width, because GNUstep's `-[NSTableColumn setHidden:]` is not honoured in layout. When it is shown again it goes after the nearest earlier column that is shown, wherever the user has dragged that one. The list then refits its flexible column (Name, or the extension list's Description).

**Order and widths**
- Header drag-reorder is allowed, but Name stays pinned first (`TreeListControl.cpp:892-905`).
- Order and widths persist (`OPT:348-349`).

**Sorting**
- Default: Percentage, descending. · Name and Last Change sort ascending on first click (`FileTreeControl.cpp:28-31`). · Name sorts by item type first, then case-insensitively by name (`IX:292-305`).

**Cell rules (`IX:169-258`)**
- **Physical Size, hardlinks:** a hardlinked file shows `⧉ <size>`; a `<Hardlinks>` index entry shows `⫘ <size>`. Clicking that cell jumps to the counterpart, and the cursor shows a hand (`FileTreeControl.cpp:129-241`). · **Items, Files, Folders:** blank for files and pseudo-items. · **Last Change:** blank for pseudo-items. Format: locale short date, two spaces, then time without seconds (`HelpersInterface.cpp:145-198`). · **Attributes:** letters `RHSACEOZ` in that order; `??????` when invalid (`HelpersInterface.cpp:200-215`). Blank for pseudo-items and MyComputer. · **Owner:** shown for files and directories only. · **Drive rows:** the name omits its `X:` prefix.

**Text colour**
- Compressed items use `#3A99E8`; encrypted items use `#008000` (`IX:260-284`, `WinDirStat.cpp:35-36`).
- *Linux:* no equivalent.

**Subtree-percentage bar colours**
- One colour per tree level, cycling through `FileTreeColorCount` levels (default 8, adjustable 1–8 by slider; `OPT:258-268,317`).
- Default colours: (64,64,140), (140,64,64), (64,140,64), (140,140,64), blue, red, lime, yellow.

---

## 4. Select Drives dialog (`RC:435-453`, `Dialogs/SelectDrivesDlg.cpp`)

**When it appears**
- At startup when there is no command-line path (`WinDirStat.cpp:489-491`). · From File › S&elect Target... (Ctrl+O) and toolbar button 1. · Title: "WinDirStat - Select Drives".

**Radio modes** (persisted as `SelectDrivesRadio`, default 0; `OPT:315`)

1. **&All Local Drives** The label gets the drive list appended, e.g. `" (C: D:)"`. Remote and SUBST drives are left out (`:383-396,466`). · 2. **&Individual Drives** A multi-select list. Changing the selection switches to this radio (`:569-580`). Focusing the list with nothing selected selects row 0. · 3. **Individual &Folder** An editable combo plus a browse button. The combo holds a most-recently-used history of `FolderHistoryCount` entries (default 10, maximum 100). Del on an open entry removes it from the history (`:632-650`). Clicking the combo selects this radio. `X:` gets a trailing `\`.

**Checkboxes**
- "Scan for duplicate files (impacts performance)": `ScanForDuplicates`, default **off** (`OPT:192`).
- "Use accelerated scanning": the NTFS MFT reader. *Windows-only.*

**OK button and confirm (`:480-510`)**
- OK is enabled when: All Local Drives: always; Individual Drives: at least one drive selected; Individual Folder: the field is non-empty and the path exists (or is UNC).
- Double-clicking a radio button confirms the dialog.

**Drive list columns (`:312-316`)**

| Column | Align | Width | Content |
|---|---|---|---|
| Name | L | 150 | Volume display name, "Label (C:)" |
| Total | R | 65 | Total size |
| Free | R | 65 | Free space |
| Used/Total (bar) | L | 100 | Owner-drawn bar, RGB(80,80,170) |
| Used/Total (percent) | R | 75 | `NN.N%` |

- Total and percent are blank for SUBST drives. · Until its query finishes, the bar cell reads "(querying...)"; on failure it reads "(unavailable)" (`:159-208`, `EN:190,300`). · Each drive is queried on its own thread. Used = (total − free) / total, or 0 when free > total (`:47-109`). · The list re-sorts as results arrive, and columns are sortable. · Drive types listed: removable, fixed, remote, CD-ROM, RAM disk (`:351-352`).

**On OK (`:408-478`, `WinDirStat.cpp:517-525`)**
- Persist the radio choice, the selected drives, and the dupes/fast-scan settings. · Switch to the All Files tab. · Open the document with the joined spec: two or more drives give a synthetic MyComputer root; one drive gives a Drive root; anything else gives a Directory root (`7da9c724:DirStatDoc.cpp:109-148`).

**Linux equivalent**
- **All local drives:** read `/proc/self/mountinfo`. Exclude pseudo filesystems: proc, sysfs, devtmpfs, tmpfs, cgroup*, squashfs, overlay (except `/`). Exclude network and FUSE filesystems: nfs*, cifs/smb3, sshfs, fuse.*. De-duplicate bind mounts by `st_dev`. · **Individual drives:** the same list. Name: "Label (mountpoint)", or just the mountpoint. Total and Free come from `statvfs`, with Free = `f_bavail`. Keep the bar and percent columns. · **Multi-mount root:** a synthetic "This Computer" node.

---

## 5. Largest Files tab (`Controls/FileTopControl.cpp`, `ItemTop.cpp`, `FileTreeView.cpp:70-81`)

**Count and ranking**
- `LargeFileCount`, set via Advanced › "Large files display count". Default **50**, range 0–10000; 0 disables the feature (`OPT:310-311`, `:24`).
- Files are ranked by **logical** size (`FileTopControl.h:30-33`).

**Structure**
- One always-expanded root row, "Largest Files" (`EN:94`).
- Each child row shows the file's **full path** in Name (`ItemTop.cpp:13-24`).

**Columns**

| Column | Align | Width |
|---|---|---|
| Name | L | 500 |
| Physical Size | R | 90 |
| Logical Size | R | 90 |
| Last Change | L | 120 |

- Default sort: Physical Size, descending.
- Name and Last Change sort ascending first.

**Updates**
- Every file found or re-stat'd is queued (`Item.cpp:79,1186`). · Each `SortItems` drains the queue and runs `partial_sort` to keep the top N. Rows are added or removed only when membership changes (`7da9c724:Controls/FileTopControl.cpp:45-126`). · During a scan this runs every ~375 ms, and only while the tab is active (`MF:884-888`). A final pass runs on completion. · Refresh and delete purge the affected subtree's files (`:109-150`).

---

## 6. Duplicates tab (`Controls/FileDupeControl.cpp`, `ItemDupe.cpp`)

*Later upstream (v2.8, `71143eb4`, with `860d840d`'s per-group fix):*
- **Deduplicate with Hardlink** (`ShowCreateHardlinkPrompt`): from the Duplicates list, with at least two files selected on one volume and the scan settled.
- Within each hash group, the first selected file stays and every other selected file in that group is replaced: a hard link to the source under a GUID-suffixed temporary name, then `MoveFileEx(…, MOVEFILE_REPLACE_EXISTING)` over the target. The temporary link is removed on failure.
- The confirmation lists only the targets.
- **LinDirStat:** only regular files (never symlinks) on one filesystem (`EXDEV` otherwise). An already-linked pair is a no-op. Before replacing, each target is compared byte for byte with its source, so a file changed since the duplicate search is refused (`ECANCELED`) and left alone. The swap is `link()` to `<target>.ldhl-XXXXXX` and then `rename()`, which is atomic. The target takes the source's permissions and owner, as any hard link does.
  - Each replaced file also gives up its own metadata for the kept file's: extended attributes, and on macOS Finder tags, the quarantine flag, ACLs and the creation date. Comparing reads both files whole, so on macOS iCloud "Optimize Mac Storage" placeholders are downloaded first; the duplicate search reads them too. APFS clones are linked like any copy, saving nothing there. A clone-based variant for Apple is a possible later addition.

**Opt-in**
- Requires `ScanForDuplicates` (the Select Drives checkbox, default off; also settable by CLI flags, `WinDirStat.cpp:399-400`). · The tab is visible only when that option is on and a root exists (`FileTabbedView.cpp:87-88`). · There is **no minimum-size option**. 0-byte files are grouped too.

**Algorithm** (runs inline on the scanner threads, per file; `FileDupeControl.cpp:21-123`)

1. **Cloud skip.** Cloud placeholders are skipped when `SkipDupeDetectionCloudLinks` is on (the default). · 2. **Size bucket.** `sizeTracker[logicalSize]` collects files by size. Hashing starts only once a bucket holds two or more files. · 3. **Tiered hashing.** Every file in the bucket is hashed in tiers (`FileDupeControl.h:40-45`):

   | Tier | Bytes hashed |
   |---|---|
   | SMALL | first **4 KiB** |
   | MEDIUM | first **1 MiB** |
   | LARGE | whole file |

   - A file's top tier depends on its size: ≤4 KiB stops at SMALL; ≤1 MiB stops at MEDIUM; anything larger goes to LARGE. Files with the same hash and the same size advance to the next tier. At the file's top tier, a match makes them duplicates. Tier flags on each file prevent re-hashing. An unreadable file is flagged SKIP.
4. **Hash function.** SHA-512, truncated to **16 bytes**, displayed as 32 lowercase hex characters (`7da9c724:Item.Extended.cpp:873-946`, `7da9c724:ItemDupe.cpp:22-23`).
5. **UI updates.** Node additions are queued and applied on the UI thread in `SortItems()` (`:125-148`).

**Presentation: a grouped tree**
- Root row: "Duplicate Files" (`EN:63`). · **Group rows**, one per hash, labelled `<hash> (<.ext1>, <.ext2>…)`: extensions are unique, cut off at ~128 characters, with `.???` for none (`ItemDupe.cpp:68-104`); sizes are summed over the group; Items = the number of files. · **File rows** under each group show the full path.

**Columns (`FileTreeView.cpp:88-94`)**

| Column | Align | Width |
|---|---|---|
| "Hash Prefix / Name" | L | 500 |
| Items | R | 70 |
| Physical Size | R | 80 |
| Logical Size | R | 80 |
| Last Change | L | 120 |

Default sort: Physical Size, descending.

**Updates**
- During a scan, every ~375 ms while the tab is active (`MF:878-882`). · Activating the tab forces a sort, showing a wait cursor (`FileTabbedView.cpp:140-149`). · On refresh or delete (`:150-261`): the affected files are unhashed; a group left with one file loses it; an empty group is removed.

---

## 7. Search (`Dialogs/SearchDlg.cpp`, `Controls/FileSearchControl.cpp`, `ItemSearch.cpp`)

*Later upstream (v2.6–v2.7, `7bfc8ccb`, `b7edc158`, `eea69dfc`; v2.9.0 `SearchDlg.cpp`, `FileSearchControl.cpp`):*
- **Folders can match:** "Files" and "Folders" checkboxes (`SearchIncludeFiles`/`SearchIncludeFolders`, both on). The searched root is never a result.
- **Size ranges:** logical and physical, each min–max with a unit (`SearchSizeMinimum/Maximum`, `SearchSizeUnits` default MiB; `SearchPhysical…`). A folder's sizes are its subtree's. The ranges are checked before the name.
- **Owner:** a case-insensitive part of the owner's name (`SearchOwner`), checked last because it is the costly test.
- **Empty term:** matches every name.
- **History:** the term box keeps a history (`SearchHistory`, `SearchHistoryCount` default 10). Picking an entry restores its Regex/Whole Phrase/Case.
- **Totals:** the results show logical and physical totals, a match inside another counted once.
- **LinDirStat:** the totals, in the current metric, go into the status text with the count. The history is stored as dictionaries rather than upstream's `\x1f`-flagged lines.
- *Later upstream (v2.6–v2.8, `9ed686b1`, `c58281b5`, `0cdff4c3`; `40d77b69:windirstat/Controls/ExtensionListControl.cpp:325-378`):* the extension list's context menu starts with **Extension - Search** (its default item, with a search icon), and a **double-click** on a row runs it. It searches the whole tree for files (not folders) with that extension: regex `GlobToRegex(".ext") + "$"`, or `^[^\.]+$` for no extension. LinDirStat follows this. Its regex follows its own extension rules (`+[LDExtensionStats extensionKeyForFilename:]`): a character before the dot (`.\.ext$`, case-insensitive), and for no extension a leading-dot name, a dotless name, or a trailing dot (`^(\.?[^.]*|.*\.)$`). So the results are exactly the files the row counts. AppKit has no bold default item, so Search is only placed first.
- *Later upstream (v2.8, `04b336dc`; `6813c201` blocks it during scans; `40d77b69:windirstat/WinDirStatModel.cpp:236-260,425-486`, `MainFrame.Commands.cpp:451-456,618-627`):* **Group Unregistered Types** (`GroupUnregisteredTypes`, default off) in Options, the extension list menu and the treemap menu, enabled once the scan has settled with the extension list shown. Extensions with no `HKEY_CLASSES_ROOT\.ext` key fold into one `⋯` row described "Grouped Extensions" ("no extension" stays separate). The colours are ranked with the group as one unit, sized by its sum, so all its members share one colour. Selecting the row highlights them all in the treemap; Search and Add to Exclusion Filter are greyed out on it. LinDirStat follows this. "Registered" means a shared-mime-info `*.ext` glob on Linux and a declared (not dynamic) `UTType` on macOS (`-[LDFileTypeDescriptions isExtensionKeyRegistered:]`); without a type database nothing is grouped. The row is shown as `…` (U+2026), because GNUstep has no font fallback and the Adwaita UI font lacks `⋯`.

**Dialog (`7da9c724:windirstat.rc:635-647`)**
- A "Search Term:" field. · Three checkboxes, all default off and persisted (`7da9c724:Options.cpp:48-51,132`): Use Regular Expressions; Case Sensitive Search; Search Whole Phrase. · OK and Cancel. OK is disabled while the term is empty or the regex is invalid. · Opened with Edit › Search... (Ctrl+F) or the toolbar. Disabled while a scan runs.

**Matching (`FileSearchControl.cpp:21-66`, `HelpersInterface.cpp:270-282`)**
- **Pattern type.** Non-regex mode treats the term as an **unanchored glob**: `*` becomes `[^\\/:]*` and `?` becomes `[^\\/:]`. Typing `*` in non-regex mode auto-ticks Whole Phrase (`SearchDlg.cpp:236-247`). · **Match mode.** Whole Phrase means a full match (`regex_match`); without it, a substring match (`regex_search`). Case-insensitive by default. · **Scope** (`7da9c724:Controls/FileSearchControl.cpp:84-105`): the whole root; **file names only**, not paths; **files only** the `<Hardlinks>` subtree is not descended. · **Execution.** Runs under a cancellable progress dialog. · **Result cap.** `SearchMaxResults`, default 10000, registry only (`OPT:196`). Beyond the cap, the largest results by logical size are kept (`:106-120`).

**Results (`SearchDlg.cpp:194-199`, `ItemSearch.cpp:15-27`)**
- The "Search Results" tab is unhidden and activated. · Root row: `Search Results (N)`, or `(N+)` when capped. · Children show full paths. · Columns are the same as Largest Files. · Default sort: **Logical** Size, descending (`FileTreeView.cpp:98-109`). · A new search replaces the old results. Refresh and delete remove the matching rows (`7da9c724:Controls/FileSearchControl.cpp:140-150`).

---

## 8. CSV save and load (`CsvLoader.cpp`)

### Save Results To CSV... (Ctrl+Alt+S; `7da9c724:DirStatDoc.cpp:1097-1109`)

The file filter is "CSV Files (*.csv) | All Files".

**Header** (localized; English shown; `CsvLoader.cpp:556-582`):

```
"Name","Files","Folders","Logical Size","Physical Size","Attributes","Last Change","WinDirStat Attributes","Index"[,"Owner"]
```

`Owner` is present only when the Owner column is shown.

**Row format (`:468-499`)**
- UTF-8, no BOM. Every row is *preceded* by `\r\n`, so there is no trailing newline.

| Field | Format |
|---|---|
| Name | quoted **full path** (MyComputer: its display name) |
| Files, Folders | decimal |
| Logical Size | decimal |
| Physical Size | raw decimal, with the hardlink de-duplication undone (`:444-466`) |
| Attributes | quoted letters, e.g. `"RHA"` |
| Last Change | UTC `YYYY-MM-DDTHH:MM:SSZ`, unquoted (`:152-159`) |
| WinDirStat Attributes | `0x%08X` item-type bits, with the hardlink, hash and ext-data flags removed |
| Index | `0x%016X` file ID (the inode, on Linux) |
| Owner | quoted |

**WinDirStat Attributes bits**

| Bit | Meaning |
|---|---|
| `0x1` | MyComputer |
| `0x2` | Drive |
| `0x4` | Dir |
| `0x8` | File |
| `0x10` | FreeSpace |
| `0x20` | Unknown |
| `0x10000000` | Root |
| `0x20000000` | Done |
| `0x00F00000` | Reparse kind |

**Row order:** depth-first pre-order. Siblings come out case-insensitively **alphabetical**. The `<Hardlinks>` container is skipped (`:416-442`).

**Quoting gap:** embedded `"` characters are not escaped. *Port:* write `""` and accept it on read.

### Load Results From CSV... (Ctrl+Alt+L; `WMA:281-294`, `CsvLoader.cpp:258-338`)

- **Columns** are matched **by localized header name**, so their order is free. All are required except Owner; a missing column fails the load.
- *Later upstream (after v2.9.3: `51f123b2`, `589e83c5`; unreleased at the pin):* Save Results appends `"ScanOutcome","ScanError"` (quoted: `not-started`, `complete`, `partial`, `cancelled`, `missing`, `connection-error`, `enumeration-error`, and the error text) and leaves Physical Size **blank** when it is unknown (a cloud file not stored locally). LinDirStat's loader matches columns by name, so it ignores the two new columns, and it reads a blank Physical Size as 0 bytes on disk. Both are pinned by `Tests/Fixtures/csv/windirstat-master-scan-outcome.csv`. A v2.9.3 export is pinned by `windirstat-2.9.3.csv` (the format above, unchanged since `7da9c724`). Sizes keep one decimal in the UI; upstream's two-decimal format (`322ee29b`) is still Dan's open call. · **Rows:** the type comes from the hex attribute column; root and drive rows use the full path as their name; every other row splits at the last separator and attaches to a parent looked up by path. · **After parsing**, every parent is sorted by physical size. · **Result:** the loaded tree becomes the document via `OnOpenDocument(newroot)` (`WM:160-203`), which calls `StartScanningEngine({})`. That only finalizes; it does **no disk I/O**. Refresh rescans from disk.

### Save Duplicates To CSV... (`7da9c724:DirStatDoc.cpp:1111-1123`, `7da9c724:CsvLoader.cpp:343-407`)

Enabled only when the Duplicates tab is visible.

```
"Hash Prefix","Name","Logical Size","Physical Size","Last Change","Attributes"
```

- One row per file, `\r\n` after each.
- *Later upstream (v2.9.0; `40d77b69:windirstat/CsvLoader.cpp:606-623,651-670`):* a seventh column, `"Sampled hash"`, unquoted `true` or `false`: `true` when the group was matched by hashing samples of a very large file ("Probable duplicates"). LinDirStat writes it and always writes `false`, because it hashes whole files. `Tests/Fixtures/csv/windirstat-2.9.3-duplicates.csv` pins the header.
- Sorted by logical size descending, then hash, then path (case-insensitive).

### Command line (`7da9c724:WinDirStat.cpp:233-236`)

- `/savetocsv <f>`: scan, save results, exit 0 on success or 1 on failure (`7da9c724:DirStatDoc.cpp:1952-1960`). · `/savedupestocsv <f>`: the same for duplicates (`7da9c724:DirStatDoc.cpp:1963-1972`). · `/loadfromcsv <f>`: load a CSV at startup.

### JSON (later upstream, v2.6, `34daeec3`; v2.9.3 `CsvLoader.cpp:11-110, 340-414, 501-583, 627-672`)

- **Chosen by extension:** a path ending in `.json` (case-insensitive, `IsJsonPath`) is JSON for Save Results, Load Results and Save Duplicates; anything else is CSV. The menu labels become **Save Results To CSV/JSON…**, **Load Results From CSV/JSON…** and **Save Duplicates To CSV/JSON…**, and the file filter "CSV/JSON Files (*.csv;*.json)". The command-line flags are renamed `/saveto`, `/savedupesto` and `/loadfrom`.
- **Results layout** (`SaveResultsJson`): `[\r\n`, then one object per row in the CSV's order, joined by `,\r\n`, then `\r\n]\r\n`. Each object is `{\r\n`, then members `  "Column": value` joined by `,\r\n`, then `\r\n}`. The keys are the CSV's (localized) column names. Files, Folders, Logical Size and Physical Size are bare numbers. Name, Attributes, Last Change, WinDirStat Attributes (`"0x%08X"`) and Index (`"0x%016X"`) are strings, plus Owner when that column is shown. The sizes, the hard-link undo and the row order are as in the CSV.
- **Escaping:** `JsonQuote` escapes only `"` and `\`. Other bytes, control characters included, are written raw.
- **Duplicates layout** (`SaveDuplicatesJson`, v2.6): the same wrapper, with members Hash Prefix, Name, Logical Size, Physical Size (numbers), Last Change and Attributes. v2.7+ adds a `Sampled hash` boolean (`ccdde6b9`).
- **Loading** (`LoadResultsJson`, `JsonReadObject`): it skips lines until `[`, then reads objects line by line. Members are matched by key in any order, unknown keys are ignored, missing ones are empty, and an object without a Name is skipped. Strings are unescaped by dropping each `\` (so `\n` reads as `n`). Rows are then built exactly as from the CSV.

*LinDirStat:* `LDCSV` picks the format the same way, writes the same layout byte for byte, and loads with the same row handling as its CSV (including #85's Windows backslash paths). The labels and panels say CSV/JSON. `--saveto`, `--savedupesto` and `--loadfrom` work alongside the old names. Differences: control characters (possible in Linux names) are written as `\u00XX`, so the file stays valid JSON. The reader decodes all JSON escapes (`\n`, `\uXXXX`, surrogate pairs) and skips nested values, which WinDirStat never writes. Duplicates JSON has v2.9.3's seven members, `"Sampled hash": false` last (LinDirStat hashes whole files). The fixture `Tests/Fixtures/csv/windirstat-drive.json` is the CSV fixture written in `SaveResultsJson`'s layout.

---

## 9. Filters and scan exclusions

### Filtering page (`RC:621-644`, `Pages/PageFiltering.cpp`, `Filtering.cpp:160-219`)

| Setting | Default | Effect |
|---|---|---|
| "Folder paths to exclude:" (multiline) | "" | Each line is matched (`regex_match`, case-insensitive) against a directory's **full path**. A match means the directory is **not added at all** (`Item.cpp:1151`, `Filtering.cpp:243-261`). |
| "File name patterns to exclude:" | "" | Matched against the **file name only** (`Item.cpp:1164-1166`, `Filtering.cpp:282-287`). |
| "Use regular expression instead of glob patterns" | off | Globs become anchored `^…$` regexes; `*` and `?` never cross `\ / :`. |
| "Exclude files less than:" N + unit (bytes, KiB, MiB, GiB, TiB) | 0, bytes | Files whose **logical** size is under the threshold are skipped (`Filtering.cpp:199-200`, `Filtering.cpp:268-273`). |

*Later upstream (v2.6–v2.9.0, `db7c9e04`, `f28e1b5f`, `b30b874c`, `80022cfe`, `fbaf5458`, `5e3dcd0e`; `Filtering.cpp`):*
- **Folder patterns match the folder and everything below it.** This applies to both exclude and include patterns (`MatchDirectoryAndDescendants`: `(?:pat)(?:\\.*)?`, with a trailing unescaped `$` dropped).
- **"Folder paths to include:" and "File name patterns to include:"** (`FilteringIncludeDirs`/`FilteringIncludeFiles`).
  - With folder includes, only files below an included folder are kept.
  - A folder is entered only when it is included, or when it is on the way to an include's fixed leading folder (`ExtractIncludeAnchor`). An include starting with a wildcard prunes no folder.
  - With file includes, only matching names are kept.
  - Exclusions win.
- **Size:** "Exclude files by size:" gets a `<`/`>` choice (`FilteringSizeComparison`, 0 = `<`).
- **Age:** a new "Exclude files by age (0 = disabled):" N days, with `<`/`>` (`FilteringMaxAgeDays`, `FilteringMaxAgeComparison`, default 1 = `>`, which leaves out files older than N days). It is measured against the last write time.
- **Changing filters refreshes everything** (`5e3dcd0e`). This replaces "Changing a filter does not rescan" below.

LinDirStat follows this, with three differences:
- **Glob includes are followed component by component.** For example, `/data/*/src` goes through `/data` and `/data/x`. Upstream prunes everything below an include's fixed leading folder, so it finds nothing for such a pattern. Regex includes prune only off their leading folder.
- **When the rescan happens:** the Preferences window applies changes live, so the rescan happens when the Filtering page is left or the window closes (with valid filters, and not for results loaded from a file).
- **The size and age filters apply to regular files**, as before.
- **Folder patterns match the path as shown in the tree.** On macOS the app standardizes a scan root (`/private/tmp/x` is scanned and shown as `/tmp/x`), so `/private/...` patterns match nothing there; exclusions always behaved this way.

The post-v2.9.0 fixes are Windows path handling (`864a22cb`, `b2963623`), a speed-up (`7b04b45e`, done here independently: files in an included folder skip the path check) and newline names (`f4a131f8`; POSIX `.` already matches newlines). None was copied; v2.9.2 and later are GPL-3.

**Pattern handling**
- Trailing `\r` and `\` are trimmed. · A bad pattern reports "Invalid filter: <token>" (`Filtering.cpp:177-196`). · Tooltip examples (`RC:35-38`): glob `C:\Windows\Sys*` or `*.exe`; regex `C:\\Windows\\Sys.*` or `.*\.exe`.

**Access and effect**
- The toolbar **Filter** button opens a sheet holding only this page (`7da9c724:WinDirStat.cpp:445-451`). · **Changing a filter does not rescan** the user must Refresh (`7da9c724:Pages/PageFiltering.cpp:121-133`). · Excluded entries count toward nothing.
- *Later upstream (v2.5.8+, `a874bcf4`, `c9501507`):* **Add to Exclusion Filter** (Edit menu and the tree, treemap and extension list context menus). For each selected drive, folder or file it appends a line: a file's **name** to the file name patterns, otherwise the full **path** to the folder patterns, regex-escaped when regular expressions are on. Then it refreshes the selection, which drops the items. On the extension list it appends `*.ext` to the file name patterns (`*.` for no extension) and refreshes everything. LinDirStat differences:
  - It leaves out scan roots and mount points, because excluding one would empty the scan.
  - It skips a pattern that is already a line.
  - Its extension pattern is `?*.ext`, or `.+\.ext` with regular expressions, so a hidden file named `.ext` (which has no extension) is not caught. Upstream writes a glob even in regex mode.
  - There is no pattern for files without an extension, because none can select names without a dot.
  - Refresh Selected now applies the filters to the refreshed item itself, as a scan of its folder does.

### Scan exclusions (Advanced page; `RC:580-619`, `OPT:165-182`, `Item.cpp:1146-1169`)

| Kind | Mount points | Junctions | Symlinks | Hidden | Protected (hidden+system) |
|---|---|---|---|---|---|
| Directory | **excluded** | **excluded** | **excluded** | included | included |
| File | – | – | **excluded** | included | included |

**What "excluded" does**
- Hidden or protected entries that are excluded are **skipped entirely**. · A directory reparse point that is not followed is still **added, as an empty leaf node** (0 read jobs), with a link or mount icon (`Item.cpp:332-353`, `WinDirStat.cpp:114-121`, `IX:408-420`). · An excluded file symlink is skipped.

**Applying changes (`PageAdvanced.cpp:25-62`)**
- Changing hidden/protected or ProcessHardlinks triggers a **full rescan**. · Turning a link exclusion *off* refreshes only the reparse-point items (`WM:265-273,389-423`). · Following any directory link type switches the progress display to pacman (§2).

**Linux mapping**

| Windows | Linux |
|---|---|
| Symlink | symlink |
| Volume mount point | crossing to another `st_dev` |
| Hidden | dot-name |
| Junction | n/a |
| Protected | n/a |

Keep the "add as a leaf, don't descend" behaviour for unfollowed links and mounts.

---

## 10. Options dialog (`7da9c724:MainFrame.cpp:1396-1424`)

**Page order:** General, Filtering, Folder List, Treemap, Cleanups, Prompts, Advanced. The last page used is remembered (`ConfigPage`). Settings are saved when the dialog closes.

### General (`RC:551-578`, `PageGeneral.cpp`)

| Setting | Default | Notes |
|---|---|---|
| Show sizes in GiB/MiB/KiB/bytes format | on | Off → `1,234,567 bytes` (`HelpersInterface.cpp:95-103`) |
| Run in portable mode | – | *Windows-only.* Linux: where the config is stored. |
| Automatically elevate on startup | off | *Windows-only; omit.* |
| Automatically resize columns | on | |
| Add to Explorer context menu | – | *Windows-only.* Linux: `.desktop` action. |
| List Style: Full Row Selection | on | |
| List Style: Show Grid | off | |
| List Style: Show Stripes | off | |
| Dark Mode: No / Yes / Use Windows Setting | Use Windows Setting | §11 |
| Language | system | |
| Use Windows settings for date/time/number formatting | on | |

- Changing dark mode or language needs a **restart** (`PageGeneral.cpp:107-110`).
- List-style changes repaint immediately.

### Filtering (§9)

### Folder List (`RC:490-517`)

| Setting | Default |
|---|---|
| Pacman Animation | on |
| Show time spent during scan | on |
| Optional Columns | §3 |
| Subtree Percentage Colors: 8 level colour buttons + level-count slider | §3 |

### Treemap (`7da9c724:windirstat.rc:514-544`; defaults at `7da9c724:Controls/TreeMap.h:222-233`)

- A live preview.
- Sliders (default %):

  | Slider | Default |
  |---|---|
  | Brightness | 88 |
  | Cushion Shading | 13 |
  | Height | 38 |
  | Scale Factor | 91 |

- Style: KDirStat (default) or SequoiaView. · Show Grid (off), Grid Color (black), Highlighting Border Color (white). · Light Incidence XY pad, default (−1, −1). · A Reset button.
- *Later upstream (v2.6 `f9ada432`, v2.8 `549d7f20`; branch colours v2.9 `d192aff3`; v2.9.3 `Controls/TreeMap.cpp:86-155, 796-859`):* **Show Folder Frames** (Treemap menu and treemap context menu, `TreeMapShowFolderFrames`, default off). Every folder except the treemap's root whose shorter side is at least `TreeMapFolderFramesDrawThreshold` pixels (default 5, 3–128, settings file only) gets a 1-pixel frame. When the folder is taller than the header and its name fits in the frame's inside less 6, it also gets a header: a strip one font height plus 2 tall, filled with the branch colour, with the name in `COLOR_WINDOWTEXT`. The children are laid out inside the frame, below the header. The frame is `DimColor` (90%) of the branch colour. `CFolderColors`: a scan root is `COLOR_WINDOW` blended 12% towards `COLOR_WINDOWTEXT`. Each folder directly below a scan root takes one of 8 palette colours (siblings ordered by physical size, then name; FNV-1a hash of the name, the next free entry on a clash), and its descendants inherit it, blended into `COLOR_WINDOW` by 22% plus 6% per level (up to 6). *LinDirStat:* `LDTreemap` lays out and paints the frames and header strips in the bitmap, with the blend colours `controlBackgroundColor` and `controlTextColor`. `LDTreemapView` draws the names with the small system font, and measures them for the fit test. With frames on, the treemap is laid out on the main thread (it needs the font), not precomputed with the scan results. Show Folder Frames is in the Treemap menu and in the treemap context menu, after Group Unregistered Types, as upstream.
- An empty treemap (a root of 0 B, such as an unreadable folder) is filled with the window colour, not drawn black (`v2.9.3:Controls/TreeMap.cpp:667-670`, `COLOR_WINDOW`). The root is still the one hit-test item. LinDirStat renders it transparent and the view shows `controlBackgroundColor`, so the theme decides the colour (#57).

### Cleanups (§1.6)

### Prompts (`7da9c724:windirstat.rc:620-633`)

| Setting | Default | Notes |
|---|---|---|
| Warn before deleting | on | Split in v2.6, below |
| Elevation prompt | on | *Windows-only* |
| Cloud-links warning during duplicate detection | on | |
| Microsoft progress dialogs | off | *Windows-only* |

*Later upstream (v2.6, `581c609d`):* "Warn before deleting" becomes one "Show confirmation before: <operation>" switch per destructive operation (`IDS_PAGE_PROMPTS_OPERATION_CONFIRMATIONs`), each defaulting on: Delete Permanently (`ShowDeletePermanentlyWarning`), Delete to Recycle Bin (`ShowDeleteToRecycleBinWarning`), Empty Recycle Bin (`ShowEmptyRecycleBinPrompt`), Deduplicate with Hardlink (`ShowCreateHardlinkPrompt`), Change Folder Dates (`ShowSetDatesPrompt`) and Remove Empty Folders (`ShowRemoveEmptyFoldersPrompt`), plus Windows-only ones (MOTW, hibernate, shadow copies, DISM). `ConfirmOperation` asks only when its switch is on, and "Do not show this message again" turns off that switch alone. LinDirStat keeps those keys, with the trash in place of the Recycle Bin. Empty Folder uses the Delete Permanently switch. An old `ShowDeleteWarning` carries over once to the delete, trash and empty-trash switches.

### Advanced (`RC:580-619`)

| Setting | Default | Notes |
|---|---|---|
| Use Backup/Restore Privileges | on | *Windows-only* |
| Skip cloud links during duplicate detection | on | |
| Scan drives and display hardlink information | on | Builds a `<Hardlinks>` pseudo-tree and de-duplicates sizes (Linux: `st_nlink`/inode) |
| Directory and file exclusions | | §9 |
| Threads per drive | 4 | 1–16 (`OPT:313-314`) |
| Large files display count | 50 | |
| Folder history entries count | 10 | |
| Reset All Preferences | | button |

**Registry-only settings:** `SearchMaxResults`=10000, `MinimizeViewThreshold`=10, `UseDrawTextCache`.

---

## 11. Dark mode (`7da9c724:DarkMode.cpp:40-129`)

**Setting.** `DarkMode`: 0 = No, 1 = Yes, 2 = Use Windows Setting (default 2, `OPT:301`). Mode 2 reads `AppsUseLightTheme` once at startup. There is no live switching: every change needs a restart.

**What changes**
- **System colours** (`7da9c724:DarkMode.cpp:80-98`):

  | Role | RGB |
  |---|---|
  | window/list | (32,32,32) |
  | text | (220,220,220) |
  | button face | (45,45,45) |
  | menu bar | (30,30,30) |
  | highlight | (0,120,215) |
  | stripes | (50,50,50) |

- **Widgets:** dialogs, menus, flat-style tab controls, list headers, scrollbars and edit fields. · **Lists:** grid lines (90,90,90) instead of (190,190,190), and the focus-rectangle colour (`WdsListControl.cpp:400-482,553`). · **Status bar:** the progress background. · **Pacman:** the "z" colour.

**What does not change**
- **Treemap cushions** keep the same colours. Only the empty-view border pen is themed (`Controls/TreeMap.cpp:175`).
- **Tree-level bar colours and extension colours** are unchanged.

*Port:* follow Adwaita light/dark through system `NSColor`s, with **no in-app dark-mode option** (AGENTS.md). Content colours stay fixed.

---

## 12. File tabbed view (`Views/FileTabbedView.cpp`, `7da9c724:MainFrame.cpp:763-787`)

**Window layout**
- The main window splits horizontally: a top row, and the **treemap** across the bottom.
- The top row splits into the **tabbed file view** on the left (~72%) and the **extension list** on the right.

**Tabs, in order (`:43-49`)**

| Tab | Shortcut | Visibility |
|---|---|---|
| All Files | Ctrl+F1 | always |
| Largest Files | Ctrl+F2 | always |
| Duplicate Files | Ctrl+F3 | only when dupes are enabled and a root exists |
| Search Results | Ctrl+F4 | hidden until the first search |
| File Watcher | – | hidden until Tools › Start File Watcher. *Windows API; Linux inotify; optional.* |

Hidden tabs are removed, not greyed (`:81-138`).

*Later upstream (v2.7, `5dc5a134`, `329f9c91`; `40d77b69:windirstat/MainFrame.Commands.cpp:733-737,783-833,865-915`, `Controls/FileWatcherControl.cpp`):* while the File Watcher tab is active, the toolbar shows a "File Watcher:" group: **Start** (enabled while not watching a scanned tree), **Pause** (stops watching; the tab and rows stay), **Auto Scroll** (`Watcher/AutoScroll`, default on: the newest change is kept in view), **Clear** (empties the rows, including those the filter hides; watching goes on), and a **Path Filter** box. The filter is a case-insensitive `std::wregex` searched for anywhere in each row's full path. It applies to the rows already listed and to every new one. Escape clears it, and Enter or Tab moves to the list. An invalid expression keeps the previous filter and frames the box in red. LinDirStat follows this, with the controls in a bar at the top of the File Watcher tab rather than in the header bar, where there's no room for a contextual group. The filter is a POSIX extended expression (as Search), matched on the path's exact bytes (`LDFileWatcherPathFilter`). An invalid one keeps the previous filter and says so in the status bar instead of a red frame, since LinDirStat draws no custom control colours. The search field's own clear button empties it.

**Tab strip**
- MFC `CTabView` default position, at the **bottom**. · The active tab's label is bold. Tabs cannot be dragged to swap. · **Tab** cycles forward through the visible tabs and **Shift+Tab** backward. Past the end, focus moves to the extension list (`:191-227`).

**Per-tab behaviour**
- Each non-tree tab is a tree-list with one expanded pseudo-root. · Each tab's column order and widths persist. · The focused list defines the selection (§0). · A new scan selects All Files (`SelectDrivesDlg.cpp:412-414`).

---

## 13. Toolbar and main menu

### 13.1 Toolbar, in order (`MC:703-731`; tooltips `EN:17-22,66,77,89,313-345`)

| # | Button | Notes |
|---|---|---|
| 1 | Open | Select Drives |
| – | separator | |
| 2 | Resume | |
| 3 | Suspend | |
| 4 | Stop | |
| – | separator | |
| 5 | Refresh All | |
| 6 | Refresh Selected | |
| – | separator | |
| 7 | Search | |
| 8 | Filter | Opens the Filtering page alone |
| – | separator | |
| 9 | Open Item | |
| 10 | Explorer | Select in file manager |
| 11 | Copy Path | |
| 12 | Command Prompt | |
| 13 | Properties | |
| – | separator | |
| 14 | Delete (to Recycle Bin) | |
| 15 | Delete Permanently | |
| – | separator | |
| 16 | Zoom In | |
| 17 | Zoom Out | |
| – | separator | |
| 18 | Manual | Help |

- Show Toolbar: F10, default on.
- Large Toolbar Icons: default off. Enabled only while the toolbar is shown (`7da9c724:MainFrame.cpp:1390-1394`).

### 13.2 Main menu (`7da9c724:windirstat.rc:166-286`; shortcuts `RC:359-416`)

**&File**
1. S&elect Target... (Ctrl+O) · 2. — · 3. Load Results From CSV... (Ctrl+Alt+L) · 4. Save Results To CSV... (Ctrl+Alt+S) · 5. Save &Duplicates To CSV... · 6. — · 7. Refresh &All (Shift+F5) · 8. Refresh &Selected (F5) · 9. — · 10. R&un Elevated (Ctrl+Alt+E). *Windows-only.* · 11. &Exit (Alt+F4)

**&Edit**
1. &Copy Path (Ctrl+C or Ctrl+Ins) · 2. — · 3. &Search... (Ctrl+F) · 4. — · 5. Compute &Hash (Ctrl+H)
*Later upstream (v2.5.8+):* Add &to Exclusion Filter goes between Search and Compute Hash, with separators around it (`a874bcf4`; §9).

**&Clean Up:** §1.1.

**&Treemap**
1. &Show Treemap ✓ (F9) · 2. Use &Logical Size ✓ (Ctrl+L; default off) · 3. Show &Extensions ✓ (default off) · 4. — · 5. Zoom &In (+) · 6. Zoom &Out (−) · 7. Zoom &Reset (Numpad . or Ctrl+.) · 8. Reselect &Child (Numpad * or Ctrl+=) · 9. Select &Parent (Numpad / or Ctrl+−)
*Later upstream (v2.6+):* this menu becomes View. After the Logical/Physical pair it gains Show &Absolute Percentages ✓ (default on, `db7af300`; §2).

**&Tools**
1. Start File Watcher ✓ · 2. Create Shadow Copy ▸ · 3. Defragment Volume ▸ · 4. Check Disk ▸

Items 2–4 have per-drive submenus filled on open (`MC:261-287`). *Windows-only; omit.*

**&Options**
1. Show &Free Space ✓ (F6) · 2. Show &Unknown ✓ (F7) · 3. — · 4. Show File &Types ✓ (F8; the extension pane; default on) · 5. &Show Treemap ✓ (F9) · 6. Show Tool&bar ✓ (F10) · 7. &Large Toolbar Icons ✓ · 8. Show S&tatusbar ✓ (F11) · 9. — · 10. &Settings (Ctrl+I)

**&Help**
1. &Help (F1) · 2. &Report Bug/Feedback... · 3. — · 4. &About

### 13.3 Other shortcuts

| Key | Action |
|---|---|
| Enter | Open |
| Alt+Enter | Properties |
| Del | Trash |
| Shift+Del | Permanent delete |
| Ctrl+E | Select in Explorer |
| Ctrl+M | Move to |
| Ctrl+P | Command Prompt |
| Ctrl+S | PowerShell |
| Ctrl+0…9 | Custom cleanups |
| Ctrl+Alt+Space | Suspend |
| Ctrl+Alt+R | Resume |
| Ctrl+Alt+T | Stop |
| Ctrl+F1…F4 | Switch tabs |

*Port note:* keep Del = Trash and Shift+Del = Permanent (as GNOME Files does). Put "Open Terminal Here" on Ctrl+T or Ctrl+P rather than Ctrl+S, which conventionally means Save.

