# WinDirStat behavioural reference for Step D

Source: `references/WinDirStat/windirstat/` (C++/MFC). This file records the behaviour a GNUstep/AppKit port must reproduce; MFC plumbing is left out. Citations are `file:line`, using these abbreviations:

| Abbrev | File |
|---|---|
| `RC` | `windirstat.rc` |
| `DOC` | `DirStatDoc.cpp` |
| `MF` | `MainFrame.cpp` |
| `OPT` | `Options.cpp` (settings and defaults) |
| `EN` | `res/langs/lang_en.txt` (English strings) |
| `IX` | `Item.Extended.cpp` |

*Windows-only* marks features with no Linux meaning. Each one gets a suggested Linux equivalent or *omit*.

---

## 0. Enablement model (applies to every selection command)

All selection-dependent commands go through one table (`DOC:873-985`). Each command declares:

- **none**: allowed with nothing selected. · **many**: allowed with more than one item selected. · **early**: allowed while a scan runs. Otherwise it needs `IsRootDone() && !IsScanRunning()`. · **focus**: only the treemap commands use this, and they require the file tree. · **types**: every selected item must be one of these types. Reserved system files block anything not typed "any". · **extra**: an additional predicate.

"Selection" means the selected rows of the list with logical focus: file tree, Largest, Duplicates or Search. A duplicate group node expands to its children (`DOC:833-866`). Item types are listed at `Item.h:48-85`.

| Command | none | many | early | types | extra | Cite |
|---|---|---|---|---|---|---|
| Open Item | n | y | **y** | Computer/Drive/Dir/File | | DOC:920 |
| Properties | n | y | **y** | Computer/Drive/Dir/File | | DOC:921 |
| Copy Path | n | y | **y** | Drive/Dir/File | | DOC:935 |
| Select in Explorer | n | y | **y** | Dir/File | | DOC:916 |
| Cmd / PowerShell here | n | y | **y** | Drive/Dir/File | | DOC:918-919 |
| Refresh Selected | n | y | n | Computer/Drive/Dir/File | | DOC:943 |
| Refresh All | y | y | n | any | | DOC:942 |
| Delete (to Bin) | n | y | n | Dir/File | not root and on a local drive | DOC:907 |
| Delete Permanently | n | y | n | Dir/File | not root | DOC:906 |
| Empty Folder | y¹ | y | n | Dir | not root | DOC:915 |
| Move to… | n | y | n | Dir/File | not root | DOC:909 |
| Compute Hash | n | **n** | y | File | | DOC:934 |
| Compress (each algorithm) | n | y | n | Dir/File | volume supports the algorithm | DOC:928-933, 987-1001 |
| Sparsify | n | y | n | File | | DOC:925 |
| Save Results | y | y | n | any | | DOC:945 |
| Save Duplicates | y | y | n | any | Duplicates tab visible | DOC:944 |
| Search… | y | y | n | any | | DOC:949 |
| Suspend | y | y | y | any | root exists, not done, not suspended | DOC:948 |
| Resume | y | y | y | any | suspended | DOC:946 |
| Stop | y | y | y | any | root exists, not done | DOC:947 |
| Zoom In | n | n | n | Drive/Dir/File | not root; not a direct child of the zoom item | DOC:953 |
| Zoom Out | y | y | n | any | zoom item ≠ root | DOC:954 |
| Zoom Reset | y | y | n | any | zoomed | DOC:952 |
| Select Parent | n | n | y | any | has a parent | DOC:951 |
| Reselect Child | y | y | y | any | reselect stack not empty | DOC:950 |
| Show Free Space / Unknown | y | y | n | any | | DOC:955-956 |

¹ Empty Folder is listed as allowing an empty selection, but the extra predicate is evaluated against `nullptr` and fails, so in practice it needs a selection.

**Port rule:** while a scan runs, every destructive action and every refresh is disabled. Open, Properties, Copy Path, Reveal and Terminal stay enabled.

---

## 1. Clean Up menu, context menus and cleanup commands

### 1.1 Clean Up menu, in order (`RC:190-237`; labels `EN:76-141`; accelerators `RC:359-416`)

1. &Open... (Enter) · 2. — · 3. Select in &Explorer... (Ctrl+E) · 4. Open in C&ommand Prompt... (Ctrl+P) · 5. Open in Power&Shell... (Ctrl+S) · 6. &Properties (Alt+Enter) · 7. — · 8. Delete Permanently (Shift+Del) · 9. &Delete (to Recycle Bin) (Del) · 10. Empty Recycle &Bin. The label gets an async suffix, " (N Items, X)" (`MF:974-1002`, `EN:143,249`). · 11. Empty Folder · 12. &Move to... (Ctrl+M) · 13. — · 14. Compress ▸: No compression, —, LZNT1, XPRESS4K, XPRESS8K, XPRESS16K, LZX. The submenu is greyed when no child is enabled (`MF:1066-1083`). *Windows-only.* · 15. Sparsify File; Optimize VHD Files; Deduplicate with &Hardlink; Remove Mark-Of-The-Web Tags. *Windows-only.* · 16. — · 17. Disable Hibernate File; Run Windows Disk Cleanup Utility; Launch Program && Features; Remove Cached Roaming Profiles; Remove Local Profiles; Remove Volume Shadow Copies (with a count/size suffix); Component Store Cleanup ▸ (three DISM verbs). *All Windows-only; omit.* · 18. — · 19. Custom Cleanup ▸, rebuilt every time the menu opens (§1.6).

### 1.2 File tree context menu (`RC:288-332`, built at `Controls/TreeListControl.cpp:870-923`)

1. Expand/Collapse. This is the bold default item. On a row with no children, the item and its separator are removed and Open becomes the default (`TreeListControl.cpp:886-898`). · 2. — · 3. Open... · 4. — · 5. Copy Path · 6. Select in Explorer... · 7. Open in Command Prompt... · 8. Open in PowerShell... · 9. Refresh Selected · 10. Properties · 11. Compute Hash · 12. — · 13. Delete Permanently · 14. Delete (to Recycle Bin) · 15. Empty Folder · 16. Move to... · 17. — · 18. Compress ▸ · 19. Sparsify File · 20. Optimize VHD Files · 21. — · 22. Custom Cleanup ▸ · 23. — · 24. Windows Explorer Menu ▸: the native shell menu, filled lazily (`MF:931-958`). *Linux: omit, or "Open With…".*

The Largest, Duplicates and Search lists are the same tree-list class and show this same popup. Enablement follows §0.

### 1.3 Treemap context menu (`RC:334-351`)

1. Zoom In · 2. Zoom Out · 3. Zoom Reset · 4. Reselect Child · 5. Select Parent · 6. — · 7. Copy Path · 8. Select in Explorer · 9. Open in Command Prompt · 10. Open in PowerShell · 11. — · 12. C&ancel

### 1.4 Command semantics

**Open (`DOC:1605-1611`, `DOC:326-360`)**
Runs the default shell verb on each selected item. For MyComputer it opens "This PC". Reserved items are skipped. *Linux:* `NSWorkspace openFile:` once per item.

**Properties (`DOC:1613-1619`)**
Runs the shell "properties" verb on each item. *Linux:* an in-app info panel with path, kind, sizes, mtime, mode, owner and nlink.

**Copy Path (`DOC:1142-1153`)**
Copies the full paths of all selected items, joined with `\r\n`. Use `\n` on Linux.

**Select in Explorer (`DOC:1288-1333`)**
Groups the items by parent directory and opens one file-manager window per parent, with those children selected. *Linux:* D-Bus `org.freedesktop.FileManager1.ShowItems`, or `NSWorkspace selectFile:inFileViewerRootedAtPath:`.

**Command Prompt Here (`DOC:1335-1356`)**
Takes the unique folders of the selection: the item itself for a directory, its parent for a file. Opens one console per folder, titled `WinDirStat - "<path>"`.

**PowerShell Here (`DOC:1358-1385`)**
Same as Command Prompt Here, using `pwsh.exe` and falling back to `powershell.exe`. *Linux:* merge both into one "Open Terminal Here" (`$TERMINAL` or `x-terminal-emulator`, with cwd set to the folder).

**Delete Permanently / Delete to Bin / Empty Folder: `DeletePhysicalItems(items, toTrash, emptyOnly)` (`DOC:443-589`)**
1. **Warning.** Shown when `ShowDeleteWarning` is on (default true, `OPT:60`). A Yes/No dialog titled "Warning", with text `IDS_DELETE_WARNING` or, for Empty Folder, `IDS_EMPTY_FOLDER_WARNING` (`EN:42,56`). It lists every path in a scrollable list (600×400). It has a "Do not show this message again." checkbox. Yes with the box ticked turns the warning off (`DOC:445-462`). Trash shows the same prompt.
2. **Selection.** Cleared, except for Empty Folder (`DOC:465-469`).
3. **Empty Folder targets.** The *children* of each selected folder are deleted, permanently (`DOC:472-477`, `1397-1400`).
4. **Permanent delete** (`DOC:487-542`), under a cancellable progress dialog sized to the item count: Walk depth-first without following reparse points. Delete the files in parallel, force-clearing read-only first. Remove the directories deepest-first. Any top-level item that still exists falls through to the shell delete in step 5.
5. **Trash** (`DOC:544-575`): one shell operation with the recycle and undo flags. The native progress UI shows only when `ShowMicrosoftProgress` is on (default off). *Linux:* `NSWorkspace recycleURLs:` or freedesktop trash.
6. **Tree update** (`DOC:577-588`): no ad-hoc node removal. The command calls `RefreshItem(items + the drive's recycler folders when trashing)`, which is `StartScanningEngine(items)`. Because the deleted paths are gone, that refresh removes their nodes and subtracts their sizes from every ancestor (next block).

**Refresh / rescan engine: `StartScanningEngine(items)` (`DOC:1769-2017`)**
1. **Prepare.** Stop any running scan. If an item is an ancestor of the zoom item, zoom to that item. Clear the reselect stack. Suspend treemap drawing (`DOC:1771-1796`). If the single item is MyComputer, use its drive children instead (`DOC:1798-1803`).
2. **Prune each item** (`DOC:1805-1862`): Drop its files from the Duplicates, Largest and Search lists. Remember expansion, scroll position and selection. If it was done, call `UpwardSubtract{SizePhysical,SizeLogical,Files,Folders}` (and extension stats), **remove all its children**, mark the item and its ancestors undone, and re-expand it. If its path no longer exists: the root unlinks to an empty document; anything else is removed from its parent, and the parent's file/folder count is decremented.
3. **Rescan** (`DOC:1867-1902`). On a worker thread, each remaining item gets one read job and goes onto a per-volume queue served by `ScanningThreads` threads. A refreshed *file* simply re-stats (`Item.cpp:940-947`).
4. **Finish** (`DOC:1911-2014`): re-create `<Free Space>`/`<Unknown>` if enabled; rebuild the hardlink items; finalize (sort, extension data); restore the treemap and extension panes; restore scroll and selection.

**Refresh Selected (F5; `DOC:1084-1090`)**
When the only selected item is the root, behaves as Refresh All. Otherwise the subtree is pruned and rescanned in place.

**Refresh All (Shift+F5; `DOC:1092-1095`)**
Re-opens the same path spec, giving a brand-new root.

**Move to… (`DOC:1402-1471`)**
Shows a folder picker, then runs one shell move. Afterwards it refreshes each unique parent of the moved items, plus the destination folder if it is inside the tree.

**Empty Recycle Bin (`DOC:1155-1175`)**
Empties all bins with no confirmation, then rescans each drive's recycler folder. *Linux:* empty `~/.local/share/Trash` and `$mnt/.Trash-$uid`, then refresh any of those folders that are in the tree.

**Compute Hash (Ctrl+H; `DOC:1621-1635`, `HelpersTasks.cpp:667-671`)**
Works on exactly one file. Shows a message box with MD5, SHA1, SHA256, SHA384 and SHA512.

**Show Free Space / Show Unknown (F6/F7; `DOC:1191-1261`)**
- Toggles the `<Free Space>` and `<Unknown>` pseudo-files under each drive (`EN:62,266`). · Persisted as `ShowFreeSpace` and `ShowUnknown`, both default false (`OPT:64,70`). · The toggle then recalculates via `StartScanningEngine({})`.

### 1.5 Prompts that gate cleanup (Prompts page, §10)

- Delete warning (above). · Custom-cleanup confirmation (§1.6). · Cloud-link warning: once per scan during duplicate detection (`Controls/FileDupeControl.cpp:41-56`). · Elevation prompt: *Windows-only*.

### 1.6 User-defined cleanups ("Custom Cleanup"; `Options.h:26-74`, `Pages/PageCleanups.cpp`, `DOC:612-767`)

**Slots.** There are 10, numbered 0–9. Slot *i* has the shortcut **Ctrl+*i*** (`RC:401-410`), and its menu text is `"<Title>\tCtrl+<i>"` (`EN:265`).

**Fields** (all default empty, false or 0; `Options.h:46-58`):

| Field | Notes |
|---|---|
| Title | Shown as `Custom Cleanup #i` while the title is "virgin" (`OPT:275-281`) |
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
| RefreshPolicy | 0 = "No refresh", 1 = "Refresh this entry", 2 = "Refresh this entry's parent" (`EN:223-225`) |

**Page layout (`RC:452-484`)**
- A listbox of the 10 titles, with Up and Down buttons. · Enabled, Title, Command Line, and the placeholder hints. · A "Works for" group: Drives, UNC Paths, Files, Folders. · Recurse into Subdirectories, Ask for Confirmation, Show Console Window, Wait for Completion. · Refresh Policy combo.

**Page rules (`PageCleanups.cpp:211-240`)**
- Every control is disabled unless Enabled is ticked. · Recurse is enabled only when Drives or Folders is ticked; otherwise it is forced off. · Recurse forces Wait on and disables the Wait checkbox. · Wait off forces the policy to No refresh. · The `%sp`/`%sn` hints are visible only when Recurse is on. · An empty title resets to the default title (`:148-166`).

**Placeholders (`DOC:746-767`)**

| Placeholder | Meaning |
|---|---|
| `%p` | full path of the item |
| `%n` | its base name |
| `%sp` | current subdirectory path (recursive mode) |
| `%sn` | current subdirectory name (recursive mode) |

Substitution goes through `>`-markers so a `%` inside a filename is safe. Paths are **not** auto-quoted.

**Menu enablement (`DOC:317-324`, `DOC:1543-1555`, `MF:1085-1105`)**
- The slot is enabled, the selection is non-empty, and the file tree has focus. The update handler also accepts the Duplicates and Largest lists. · **Every** selected item matches a ticked type: drive, dir, file or UNC. · The submenu is greyed when no slot is enabled.

**Execution, per selected item (`DOC:1557-1587`)**
1. **Confirm.** When asked for, show a Yes/No box: "You are about to call a [Recursive] Custom Cleanup '<title>' on '<path>'. Continue?" (`EN:238,264`). No skips that item. · 2. **Check the path.** A missing path shows an error and skips the item (`DOC:628-664`). · 3. **Run** `%COMSPEC% /C <cmd>` with cwd set to the directory (for a file, its parent). The console is hidden unless ShowConsoleWindow is ticked. If Wait is on, wait (`DOC:715-744`). · 4. **Recursive mode** (`DOC:693-713`): post-order depth-first over the subdirectories, following only allowed reparse points. The command runs in each one and always waits. · 5. **Refresh.** Queued items get the refresh policy (entry, or parent; parent falls back to the item if it is the root). This only happens if Wait was on (`DOC:666-691`).

*Linux:* use `/bin/sh -c`. "Show console" becomes "run in terminal". "UNC" becomes network mounts, or is dropped.

---

## 2. Scan-time tree, Pacman and progress

**The tree is live during the scan.**
- `OnOpenDocument` creates the root, sends `HINT_NEWROOT` so the root row appears at once, then starts the engine (`DOC:93-157`). · Children are inserted as they are discovered: `AddChild` on a visible, expanded parent marshals `OnChildAdded` to the UI thread (`Item.cpp:136-142`). · **The treemap and extension list are collapsed during the scan.** Their splitter is set to 1.0 and treemap drawing is suspended (`DOC:96-97,1796`, `MF:801-815`). · After the scan they are restored: treemap at 0.5, extension pane at 0.72 (`MF:806-826`, `DOC:1995-2001`).

**UI timer: 25 ms (`MF:712`, `MF:840-878`)**
- While scanning and not suspended, every tick: updates the progress display; calls `FileTree SortItems()`, which re-sorts and repaints rows and so advances the pacmen.
- Every 15th tick (~375 ms): re-sorts the Duplicates tab, if it is active; re-sorts the Largest tab, if it is active; refreshes the status text and RAM display.

**Per-row Pacman, in the Subtree Percentage column (`IX:26-72`)**
- **Read-job mode.** A row is in read-job mode while its *parent* is not done; the root uses its own done state (`MustShowReadJobs`, `IX:1001-1009`).
- **Cell content.** Read-job mode, PacmanAnimation on (default true, `OPT:46`), item not done: an animated pacman. Read-job mode otherwise: the text `[1 Read Job]` or `[N Read Jobs]` (`IX:105-115`, `EN:144,255`). Out of read-job mode: the percentage bar, indented by level (`IX:65-70`). In read-job mode the column sorts by read-job count (`IX:210-219`).
- **Percentage column.** Shows `[elapsed]` when `ShowTimeSpent` is on (default true, `OPT:66`) and the row is in read-job mode. The **root row always** shows `[elapsed]`. Otherwise it shows `NN.N%` (`IX:120-125`).
- **Driving the pacmen.** Each entry a scanner thread adds walks up its ancestors. An ancestor with 0 read jobs stops its pacman; the others advance (`IX:611-623`, `Item.cpp:936-958`).
- **Animation** (`Controls/PacMan.cpp:21-130`): It moves 0.09 px/ms, bouncing between the cell edges. The mouth changes 0.003/ms, opening to at most 90°. Fill `#FCC92F` with a black outline. After more than 750 ms with no update it stops and draws three "z"s (`#888888` in dark mode). The global suspend flag freezes it.

**Status-bar progress (`MF:424-446`, `MF:500-555`, `IX:423-465`)**
- **Range.** For a drive or MyComputer root, the range is the used bytes, total − free. · **Range forced to 0** for a folder root, **or** when any of ExcludeVolumeMountPoints, ExcludeJunctions or ExcludeSymbolicLinksDirectory is off (the traversal can leave the volume). · **Range > 0:** a progress bar in status pane 0; position = drive size − free-space item, capped at 100%; window title prefixed `"NN% "`, with `(Suspended)` appended when suspended. · **Range = 0:** a pacman in status pane 0; title prefixed `"Scanning "` (plus `(Suspended)`; `EN:241,258`). · **Completion** (`MF:459-474`): clear the prefix, remove the widget, and do a final sort of the tree, Duplicates and Largest lists.

**Suspend / Resume / Stop**
- **Suspend** (Ctrl+Alt+Space): every per-volume queue blocks workers in `WaitIfSuspended`, the pacmen freeze, and the taskbar shows paused (`DOC:1695-1704`, `MF:479-498`). · **Resume** (Ctrl+Alt+R): `DOC:1706-1713`. · **Stop** (Ctrl+Alt+T): cancels the queues and keeps the partial tree (`DOC:1715-1738`).

**Status bar panes (`MF:664-666`, `MF:1202-1246`)**
- **Pane 0:** "Ready" (`EN:71`). It also hosts the progress widget. Treemap hover shows the hovered path (and its size in pane 1). After the scan, one selected item shows its full path. With the extension list focused it shows `*.<ext>`. · **Pane 1:** `Physical Size: ∑ <sum of selected>`. · **Pane 2:** process RAM.

---

## 3. File tree columns (`Item.h:29-43`, `Views/FileTreeView.cpp:27-53`)

| # | Column | Align | Width | Optional? | Default | Setting |
|---|---|---|---|---|---|---|
| 0 | Name | L | 250 | fixed | – | – |
| 1 | Subtree Percentage | R | bar+30 | fixed | – | – |
| 2 | Percentage | R | 90 | fixed | – | – |
| 3 | Physical Size | R | 90 | opt | **on** | ShowColumnSizePhysical (`OPT:59`) |
| 4 | Logical Size | R | 90 | opt | **on** | ShowColumnSizeLogical (`OPT:58`) |
| 5 | Items | R | 90 | opt | off | ShowColumnItems (`OPT:55`) |
| 6 | Files | R | 90 | opt | **on** | ShowColumnFiles (`OPT:53`) |
| 7 | Folders | R | 90 | opt | off | ShowColumnFolders (`OPT:54`) |
| 8 | Last Change | L | 120 | opt | **on** | ShowColumnLastChange (`OPT:56`) |
| 9 | Attributes | L | 90 | opt | off | ShowColumnAttributes (`OPT:52`) |
| 10 | Owner | L | 200 | opt | off | ShowColumnOwner (`OPT:57`) |

**Toggling columns**
- The **only** toggle is Options › Folder List › "Optional Columns" (`RC:486-512`). There is **no header context menu**.
- On OK, if anything changed, `CreateColumns()` runs (`Pages/PageFileTree.cpp:112-145`, `FileTreeView.cpp:37-52`): 1. reset the sort to Percentage, descending; 2. delete all optional columns; 3. re-add the enabled ones in the fixed order above.

**Order and widths**
- Header drag-reorder is allowed, but Name stays pinned first (`TreeListControl.cpp:937-949`).
- Order and widths persist (`OPT:120-121`).

**Sorting**
- Default: Percentage, descending. · Name and Last Change sort ascending on first click (`FileTreeControl.cpp:26-29`). · Name sorts by item type first, then case-insensitively by name (`IX:204-208`).

**Cell rules (`IX:74-163`)**
- **Physical Size, hardlinks:** a hardlinked file shows `⧉ <size>`; a `<Hardlinks>` index entry shows `⫘ <size>`. Clicking that cell jumps to the counterpart, and the cursor shows a hand (`FileTreeControl.cpp:38-112`). · **Items, Files, Folders:** blank for files and pseudo-items. · **Last Change:** blank for pseudo-items. Format: locale short date, two spaces, then time without seconds (`HelpersInterface.cpp:145-163`). · **Attributes:** letters `RHSACEOZ` in that order; `??????` when invalid (`HelpersInterface.cpp:165-180`). Blank for pseudo-items and MyComputer. · **Owner:** shown for files and directories only. · **Drive rows:** the name omits its `X:` prefix.

**Text colour**
- Compressed items use `#3A99E8`; encrypted items use `#008000` (`IX:165-188`, `WinDirStat.cpp:46-47`).
- *Linux:* no equivalent.

**Subtree-percentage bar colours**
- One colour per tree level, cycling through `FileTreeColorCount` levels (default 8, adjustable 1–8 by slider; `OPT:83-90,102`).
- Default colours: (64,64,140), (140,64,64), (64,140,64), (140,140,64), blue, red, lime, yellow.

---

## 4. Select Drives dialog (`RC:435-451`, `Dialogs/SelectDrivesDlg.cpp`)

**When it appears**
- At startup when there is no command-line path (`WinDirStat.cpp:404`). · From File › S&elect Target... (Ctrl+O) and toolbar button 1. · Title: "WinDirStat - Select Drives".

**Radio modes** (persisted as `SelectDrivesRadio`, default 0; `OPT:101`)

1. **&All Local Drives** The label gets the drive list appended, e.g. `" (C: D:)"`. Remote and SUBST drives are left out (`:432-445,496`). · 2. **&Individual Drives** A multi-select list. Changing the selection switches to this radio (`:585-592`). Focusing the list with nothing selected selects row 0. · 3. **Individual &Folder** An editable combo plus a browse button. The combo holds a most-recently-used history of `FolderHistoryCount` entries (default 10, maximum 100). Del on an open entry removes it from the history (`:640-682`). Clicking the combo selects this radio. `X:` gets a trailing `\`.

**Checkboxes**
- "Scan for duplicate files (impacts performance)": `ScanForDuplicates`, default **off** (`OPT:47`).
- "Use accelerated scanning": the NTFS MFT reader. *Windows-only.*

**OK button and confirm (`:516-539`)**
- OK is enabled when: All Local Drives: always; Individual Drives: at least one drive selected; Individual Folder: the field is non-empty and the path exists (or is UNC).
- Double-clicking a radio button confirms the dialog.

**Drive list columns (`:378-382`)**

| Column | Align | Width | Content |
|---|---|---|---|
| Name | L | 150 | Volume display name, "Label (C:)" |
| Total | R | 65 | Total size |
| Free | R | 65 | Free space |
| Used/Total (bar) | L | 100 | Owner-drawn bar, RGB(80,80,170) |
| Used/Total (percent) | R | 75 | `NN.N%` |

- Total and percent are blank for SUBST drives. · Until its query finishes, the bar cell reads "(querying...)"; on failure it reads "(unavailable)" (`:185-233`, `EN:142,230`). · Each drive is queried on its own thread. Used = (total − free) / total, or 0 when free > total (`:65-112`). · The list re-sorts as results arrive, and columns are sortable. · Drive types listed: removable, fixed, remote, CD-ROM, RAM disk (`:415`).

**On OK (`:458-512`, `WinDirStat.cpp:424-433`)**
- Persist the radio choice, the selected drives, and the dupes/fast-scan settings. · Switch to the All Files tab. · Open the document with the joined spec: two or more drives give a synthetic MyComputer root; one drive gives a Drive root; anything else gives a Directory root (`DOC:109-148`).

**Linux equivalent**
- **All local drives:** read `/proc/self/mountinfo`. Exclude pseudo filesystems: proc, sysfs, devtmpfs, tmpfs, cgroup*, squashfs, overlay (except `/`). Exclude network and FUSE filesystems: nfs*, cifs/smb3, sshfs, fuse.*. De-duplicate bind mounts by `st_dev`. · **Individual drives:** the same list. Name: "Label (mountpoint)", or just the mountpoint. Total and Free come from `statvfs`, with Free = `f_bavail`. Keep the bar and percent columns. · **Multi-mount root:** a synthetic "This Computer" node.

---

## 5. Largest Files tab (`Controls/FileTopControl.cpp`, `ItemTop.cpp`, `FileTreeView.cpp:116-136`)

**Count and ranking**
- `LargeFileCount`, set via Advanced › "Large files display count". Default **50**, range 0–10000; 0 disables the feature (`OPT:98`, `:40`).
- Files are ranked by **logical** size (`:66,90`).

**Structure**
- One always-expanded root row, "Largest Files" (`EN:73`).
- Each child row shows the file's **full path** in Name (`ItemTop.cpp:47-59`).

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
- Every file found or re-stat'd is queued (`Item.cpp:932,944`). · Each `SortItems` drains the queue and runs `partial_sort` to keep the top N. Rows are added or removed only when membership changes (`:45-126`). · During a scan this runs every ~375 ms, and only while the tab is active (`MF:870-874`). A final pass runs on completion. · Refresh and delete purge the affected subtree's files (`:128-161`).

---

## 6. Duplicates tab (`Controls/FileDupeControl.cpp`, `ItemDupe.cpp`)

**Opt-in**
- Requires `ScanForDuplicates` (the Select Drives checkbox, default off; also settable by CLI flags, `WinDirStat.cpp:255-260`). · The tab is visible only when that option is on and a root exists (`FileTabbedView.cpp:58-59`). · There is **no minimum-size option**. 0-byte files are grouped too.

**Algorithm** (runs inline on the scanner threads, per file; `FileDupeControl.cpp:38-161`)

1. **Cloud skip.** Cloud placeholders are skipped when `SkipDupeDetectionCloudLinks` is on (the default). · 2. **Size bucket.** `sizeTracker[logicalSize]` collects files by size. Hashing starts only once a bucket holds two or more files. · 3. **Tiered hashing.** Every file in the bucket is hashed in tiers (`FileDupeControl.h:53-58`):

   | Tier | Bytes hashed |
   |---|---|
   | SMALL | first **4 KiB** |
   | MEDIUM | first **1 MiB** |
   | LARGE | whole file |

   - A file's top tier depends on its size: ≤4 KiB stops at SMALL; ≤1 MiB stops at MEDIUM; anything larger goes to LARGE. Files with the same hash and the same size advance to the next tier. At the file's top tier, a match makes them duplicates. Tier flags on each file prevent re-hashing. An unreadable file is flagged SKIP.
4. **Hash function.** SHA-512, truncated to **16 bytes**, displayed as 32 lowercase hex characters (`IX:873-946`, `ItemDupe.cpp:22-23`).
5. **UI updates.** Node additions are queued and applied on the UI thread in `SortItems()` (`:163-181`).

**Presentation: a grouped tree**
- Root row: "Duplicate Files" (`EN:50`). · **Group rows**, one per hash, labelled `<hash> (<.ext1>, <.ext2>…)`: extensions are unique, cut off at ~128 characters, with `.???` for none (`ItemDupe.cpp:131-163`); sizes are summed over the group; Items = the number of files. · **File rows** under each group show the full path.

**Columns (`FileTreeView.cpp:154-161`)**

| Column | Align | Width |
|---|---|---|
| "Hash Prefix / Name" | L | 500 |
| Items | R | 70 |
| Physical Size | R | 80 |
| Logical Size | R | 80 |
| Last Change | L | 120 |

Default sort: Physical Size, descending.

**Updates**
- During a scan, every ~375 ms while the tab is active (`MF:864-868`). · Activating the tab forces a sort, showing a wait cursor (`FileTabbedView.cpp:84-94`). · On refresh or delete (`:183-282`): the affected files are unhashed; a group left with one file loses it; an empty group is removed.

---

## 7. Search (`Dialogs/SearchDlg.cpp`, `Controls/FileSearchControl.cpp`, `ItemSearch.cpp`)

**Dialog (`RC:635-647`)**
- A "Search Term:" field. · Three checkboxes, all default off and persisted (`OPT:48-51,132`): Use Regular Expressions; Case Sensitive Search; Search Whole Phrase. · OK and Cancel. OK is disabled while the term is empty or the regex is invalid. · Opened with Edit › Search... (Ctrl+F) or the toolbar. Disabled while a scan runs.

**Matching (`FileSearchControl.cpp:37-56`, `HelpersInterface.cpp:231-243`)**
- **Pattern type.** Non-regex mode treats the term as an **unanchored glob**: `*` becomes `[^\\/:]*` and `?` becomes `[^\\/:]`. Typing `*` in non-regex mode auto-ticks Whole Phrase (`SearchDlg.cpp:103-117`). · **Match mode.** Whole Phrase means a full match (`regex_match`); without it, a substring match (`regex_search`). Case-insensitive by default. · **Scope** (`:84-105`): the whole root; **file names only**, not paths; **files only** the `<Hardlinks>` subtree is not descended. · **Execution.** Runs under a cancellable progress dialog. · **Result cap.** `SearchMaxResults`, default 10000, registry only (`OPT:51`). Beyond the cap, the largest results by logical size are kept (`:107-118`).

**Results (`SearchDlg.cpp:93-100`, `ItemSearch.cpp:46-57`)**
- The "Search Results" tab is unhidden and activated. · Root row: `Search Results (N)`, or `(N+)` when capped. · Children show full paths. · Columns are the same as Largest Files. · Default sort: **Logical** Size, descending (`FileTreeView.cpp:185-189`). · A new search replaces the old results. Refresh and delete remove the matching rows (`:140-150`).

---

## 8. CSV save and load (`CsvLoader.cpp`)

### Save Results To CSV... (Ctrl+Alt+S; `DOC:1097-1109`)

The file filter is "CSV Files (*.csv) | All Files".

**Header** (localized; English shown; `CsvLoader.cpp:264-282`):

```
"Name","Files","Folders","Logical Size","Physical Size","Attributes","Last Change","WinDirStat Attributes","Index"[,"Owner"]
```

`Owner` is present only when the Owner column is shown.

**Row format (`:318-338`)**
- UTF-8, no BOM. Every row is *preceded* by `\r\n`, so there is no trailing newline.

| Field | Format |
|---|---|
| Name | quoted **full path** (MyComputer: its display name) |
| Files, Folders | decimal |
| Logical Size | decimal |
| Physical Size | raw decimal, with the hardlink de-duplication undone (`:284-315`) |
| Attributes | quoted letters, e.g. `"RHA"` |
| Last Change | UTC `YYYY-MM-DDTHH:MM:SSZ`, unquoted (`:62-69`) |
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

**Row order:** depth-first pre-order. Siblings come out case-insensitively **alphabetical**. The `<Hardlinks>` container is skipped (`:228-258`).

**Quoting gap:** embedded `"` characters are not escaped. *Port:* write `""` and accept it on read.

### Load Results From CSV... (Ctrl+Alt+L; `DOC:1125-1140`, `CsvLoader.cpp:101-226`)

- **Columns** are matched **by localized header name**, so their order is free. All are required except Owner; a missing column fails the load. · **Rows:** the type comes from the hex attribute column; root and drive rows use the full path as their name; every other row splits at the last separator and attaches to a parent looked up by path. · **After parsing**, every parent is sorted by physical size. · **Result:** the loaded tree becomes the document via `OnOpenDocument(newroot)` (`DOC:159-191`), which calls `StartScanningEngine({})`. That only finalizes; it does **no disk I/O**. Refresh rescans from disk.

### Save Duplicates To CSV... (`DOC:1111-1123`, `:343-407`)

Enabled only when the Duplicates tab is visible.

```
"Hash Prefix","Name","Logical Size","Physical Size","Last Change","Attributes"
```

- One row per file, `\r\n` after each.
- Sorted by logical size descending, then hash, then path (case-insensitive).

### Command line (`WinDirStat.cpp:233-236`)

- `/savetocsv <f>`: scan, save results, exit 0 on success or 1 on failure (`DOC:1952-1960`). · `/savedupestocsv <f>`: the same for duplicates (`DOC:1963-1972`). · `/loadfromcsv <f>`: load a CSV at startup.

---

## 9. Filters and scan exclusions

### Filtering page (`RC:604-618`, `Pages/PageFiltering.cpp`, `OPT:201-227`)

| Setting | Default | Effect |
|---|---|---|
| "Folder paths to exclude:" (multiline) | "" | Each line is matched (`regex_match`, case-insensitive) against a directory's **full path**. A match means the directory is **not added at all** (`Item.cpp:891-897`). |
| "File name patterns to exclude:" | "" | Matched against the **file name only** (`Item.cpp:916-921`). |
| "Use regular expression instead of glob patterns" | off | Globs become anchored `^…$` regexes; `*` and `?` never cross `\ / :`. |
| "Exclude files less than:" N + unit (bytes, KiB, MiB, GiB, TiB) | 0, bytes | Files whose **logical** size is under the threshold are skipped (`OPT:226`, `Item.cpp:923-927`). |

**Pattern handling**
- Trailing `\r` and `\` are trimmed. · A bad pattern reports "Invalid filter: <token>" (`OPT:210-222`). · Tooltip examples (`RC:34-37`): glob `C:\Windows\Sys*` or `*.exe`; regex `C:\\Windows\\Sys.*` or `.*\.exe`.

**Access and effect**
- The toolbar **Filter** button opens a sheet holding only this page (`WinDirStat.cpp:445-451`). · **Changing a filter does not rescan** the user must Refresh (`PageFiltering.cpp:121-133`). · Excluded entries count toward nothing.

### Scan exclusions (Advanced page; `RC:573-602`, `OPT:32-39`, `Item.cpp:886-914`)

| Kind | Mount points | Junctions | Symlinks | Hidden | Protected (hidden+system) |
|---|---|---|---|---|---|
| Directory | **excluded** | **excluded** | **excluded** | included | included |
| File | – | – | **excluded** | included | included |

**What "excluded" does**
- Hidden or protected entries that are excluded are **skipped entirely**. · A directory reparse point that is not followed is still **added, as an empty leaf node** (0 read jobs), with a link or mount icon (`Item.cpp:251-266`, `WinDirStat.cpp:117-124`, `IX:303-320`). · An excluded file symlink is skipped.

**Applying changes (`PageAdvanced.cpp:102-146`)**
- Changing hidden/protected or ProcessHardlinks triggers a **full rescan**. · Turning a link exclusion *off* refreshes only the reparse-point items (`DOC:246-254,362-396`). · Following any directory link type switches the progress display to pacman (§2).

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

## 10. Options dialog (`MF:1396-1424`)

**Page order:** General, Filtering, Folder List, Treemap, Cleanups, Prompts, Advanced. The last page used is remembered (`ConfigPage`). Settings are saved when the dialog closes.

### General (`RC:546-571`, `PageGeneral.cpp`)

| Setting | Default | Notes |
|---|---|---|
| Show sizes in GiB/MiB/KiB/bytes format | on | Off → `1,234,567 bytes` (`HelpersInterface.cpp:94-102`) |
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

- Changing dark mode or language needs a **restart** (`PageGeneral.cpp:211-217`).
- List-style changes repaint immediately.

### Filtering (§9)

### Folder List (`RC:486-512`)

| Setting | Default |
|---|---|
| Pacman Animation | on |
| Show time spent during scan | on |
| Optional Columns | §3 |
| Subtree Percentage Colors: 8 level colour buttons + level-count slider | §3 |

### Treemap (`RC:514-544`; defaults at `Controls/TreeMap.h:222-233`)

- A live preview.
- Sliders (default %):

  | Slider | Default |
  |---|---|
  | Brightness | 88 |
  | Cushion Shading | 13 |
  | Height | 38 |
  | Scale Factor | 91 |

- Style: KDirStat (default) or SequoiaView. · Show Grid (off), Grid Color (black), Highlighting Border Color (white). · Light Incidence XY pad, default (−1, −1). · A Reset button.

### Cleanups (§1.6)

### Prompts (`RC:620-633`)

| Setting | Default | Notes |
|---|---|---|
| Warn before deleting | on | |
| Elevation prompt | on | *Windows-only* |
| Cloud-links warning during duplicate detection | on | |
| Microsoft progress dialogs | off | *Windows-only* |

### Advanced (`RC:573-602`)

| Setting | Default | Notes |
|---|---|---|
| Use Backup/Restore Privileges | on | *Windows-only* |
| Skip cloud links during duplicate detection | on | |
| Scan drives and display hardlink information | on | Builds a `<Hardlinks>` pseudo-tree and de-duplicates sizes (Linux: `st_nlink`/inode) |
| Directory and file exclusions | | §9 |
| Threads per drive | 4 | 1–16 (`OPT:100`) |
| Large files display count | 50 | |
| Folder history entries count | 10 | |
| Reset All Preferences | | button |

**Registry-only settings:** `SearchMaxResults`=10000, `MinimizeViewThreshold`=10, `UseDrawTextCache`.

---

## 11. Dark mode (`DarkMode.cpp:40-129`)

**Setting.** `DarkMode`: 0 = No, 1 = Yes, 2 = Use Windows Setting (default 2, `OPT:96`). Mode 2 reads `AppsUseLightTheme` once at startup. There is no live switching: every change needs a restart.

**What changes**
- **System colours** (`:80-98`):

  | Role | RGB |
  |---|---|
  | window/list | (32,32,32) |
  | text | (220,220,220) |
  | button face | (45,45,45) |
  | menu bar | (30,30,30) |
  | highlight | (0,120,215) |
  | stripes | (50,50,50) |

- **Widgets:** dialogs, menus, flat-style tab controls, list headers, scrollbars and edit fields. · **Lists:** grid lines (90,90,90) instead of (190,190,190), and the focus-rectangle colour (`WdsListControl.cpp:342-454,523`). · **Status bar:** the progress background. · **Pacman:** the "z" colour.

**What does not change**
- **Treemap cushions** keep the same colours. Only the empty-view border pen is themed (`Controls/TreeMap.cpp:121`).
- **Tree-level bar colours and extension colours** are unchanged.

*Port:* follow Adwaita light/dark through system `NSColor`s, with **no in-app dark-mode option** (AGENTS.md). Content colours stay fixed.

---

## 12. File tabbed view (`Views/FileTabbedView.cpp`, `MF:763-787`)

**Window layout**
- The main window splits horizontally: a top row, and the **treemap** across the bottom.
- The top row splits into the **tabbed file view** on the left (~72%) and the **extension list** on the right.

**Tabs, in order (`:35-44`)**

| Tab | Shortcut | Visibility |
|---|---|---|
| All Files | Ctrl+F1 | always |
| Largest Files | Ctrl+F2 | always |
| Duplicate Files | Ctrl+F3 | only when dupes are enabled and a root exists |
| Search Results | Ctrl+F4 | hidden until the first search |
| File Watcher | – | hidden until Tools › Start File Watcher. *Windows API; Linux inotify; optional.* |

Hidden tabs are removed, not greyed (`:49-77`).

**Tab strip**
- MFC `CTabView` default position, at the **bottom**. · The active tab's label is bold. Tabs cannot be dragged to swap. · **Tab** cycles forward through the visible tabs and **Shift+Tab** backward. Past the end, focus moves to the extension list (`:96-129`).

**Per-tab behaviour**
- Each non-tree tab is a tree-list with one expanded pseudo-root. · Each tab's column order and widths persist. · The focused list defines the selection (§0). · A new scan selects All Files (`SelectDrivesDlg.cpp:508-510`).

---

## 13. Toolbar and main menu

### 13.1 Toolbar, in order (`MF:626-653`; tooltips `EN:10-15,53,61,69,232-263`)

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
- Large Toolbar Icons: default off. Enabled only while the toolbar is shown (`MF:1390-1394`).

### 13.2 Main menu (`RC:166-286`; shortcuts `RC:359-416`)

**&File**
1. S&elect Target... (Ctrl+O) · 2. — · 3. Load Results From CSV... (Ctrl+Alt+L) · 4. Save Results To CSV... (Ctrl+Alt+S) · 5. Save &Duplicates To CSV... · 6. — · 7. Refresh &All (Shift+F5) · 8. Refresh &Selected (F5) · 9. — · 10. R&un Elevated (Ctrl+Alt+E). *Windows-only.* · 11. &Exit (Alt+F4)

**&Edit**
1. &Copy Path (Ctrl+C or Ctrl+Ins) · 2. — · 3. &Search... (Ctrl+F) · 4. — · 5. Compute &Hash (Ctrl+H)

**&Clean Up:** §1.1.

**&Treemap**
1. &Show Treemap ✓ (F9) · 2. Use &Logical Size ✓ (Ctrl+L; default off) · 3. Show &Extensions ✓ (default off) · 4. — · 5. Zoom &In (+) · 6. Zoom &Out (−) · 7. Zoom &Reset (Numpad . or Ctrl+.) · 8. Reselect &Child (Numpad * or Ctrl+=) · 9. Select &Parent (Numpad / or Ctrl+−)

**&Tools**
1. Start File Watcher ✓ · 2. Create Shadow Copy ▸ · 3. Defragment Volume ▸ · 4. Check Disk ▸

Items 2–4 have per-drive submenus filled on open (`MF:1140-1170`). *Windows-only; omit.*

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

