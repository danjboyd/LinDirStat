# Performance

Parity plan item L13: scans of a million files and more, the time from
Stop to the final display, and the memory of duplicate detection.

## Measuring

Headless (model only, no display):

```sh
scripts/bench-scan.sh PATH [--runs N] [--stop-after SECONDS] [--logical] [--no-results]
```

It builds `Tools/lindirstat-bench` and runs it with 1 and 4 threads,
duplicate detection off and on. Per run it prints the scan (directory read)
time, the finalize time (totals and sort), the completion work done on the
scanning thread (`results_s`), with `--stop-after` the time from Stop to the
completion block, with `--no-results` what the main thread did before this
work (extension list, treemap layout and render, Largest Files), and RSS.

In the app, `LINDIRSTAT_PROFILE=1` logs each step of a scan's completion,
the time from completion (and from Stop) to the next display, and every
main-thread stall over 100 ms (a watchdog thread pings the main queue every
10 ms; `LDProfiling`). `LINDIRSTAT_PROFILE_STOP_AFTER=SECONDS` presses Stop
automatically. Run it on a private display with a private GNUstep home:

```sh
LINDIRSTAT_PROFILE=1 LINDIRSTAT_PROFILE_STOP_AFTER=1.5 LINDIRSTAT_SCAN_PATH=/some/tree \
DISPLAY=:89 DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent XDG_DATA_HOME=/tmp/x/data \
  scripts/run-isolated.sh /tmp/x/gshome
```

Test tree: 1,200,000 sparse files (5% empty, 70% of 1 B–64 KiB, 25% of
64 KiB–50 MB, so most small sizes repeat) in 61,591 folders, made by a small
C generator on the real disk (a tmpfs runs out of inodes). Sizes are logical
(Use Logical Size), since sparse files have no physical size. The machine
was shared and loaded (load average around 30 on 14 cores), so scan read
times vary by ±50% between runs; the other numbers are steadier.

## What was slow

| Step (1.2M files, 4 threads) | Before | Where |
| --- | --- | --- |
| Finalize: `recalculateAggregateSize` then `sortChildrenByMetric:` | 0.69 s (1.0–1.2 s with the physical metric) | scan thread, serial, two walks, `NSArray` sort with a message per comparison |
| Extension statistics | 0.40 s | main thread, a string-keyed dictionary lookup per file |
| Treemap layout | 0.56 s | main thread (first draw), an autorelease pool and three messages per cell, `subarrayWithRange:` per folder |
| Treemap render | 0.17 s | main thread (first draw) |
| Largest Files | 0.27 s | main thread, a separate walk |
| Release of the arrays replaced by the final sort | ~0.1 s | main thread |
| Freeing the previous tree on rescan | 0.2–0.7 s | main thread |
| Duplicate updates while hashing | 250–570 ms stall every 0.5 s | main thread: sorting the groups, then checking every group member is still in the tree |

## Changes

- `-[LDFileNode finishTreeSortedByMetric:retiring:]` totals and sorts in one
  bottom-up pass. The top levels are split into up to 256 subtrees finished
  in parallel with `dispatch_apply`, then the folders above them, deepest
  first. Each folder's children are sorted with `qsort` on precomputed
  sizes and stored in an exact-size `NSArray`. Same results as before
  (`LDScanResultsTests`).
- `LDScanResults`: when the scan is started with an `LDScanResultsRequest`
  (AppController does this for every scan), the scanning thread works out,
  after the final sort, the extension statistics, Largest Files (one walk,
  extension keys counted by pointer since the scanner interns them) and the
  treemap at the view's current size, laid out alongside the walk and
  rendered with the statistics' colours. `-finishAsyncScan` takes them as
  they are; `LDTreemapView` adopts the treemap only if root, metric,
  options and size still match (otherwise it renders as before), and it is
  not used when `<Free Space>`/`<Unknown>` were added to the tree.
- `LDTreemap` layout: sizes are read once per folder into a reused buffer,
  no sub-arrays, one autorelease pool per laid-out folder instead of per
  cell: 0.56 s to 0.33 s.
- The children arrays replaced by the final sort, and the previous tree and
  scan session on a new scan, are released on a background queue once the
  main thread no longer reads them.
- Duplicates: update batches (groups so far, sorted) are prepared on a
  serial background queue and only handed to the main queue; a cancelled
  collector sorts its groups there too. The Duplicates tab skips the
  still-in-tree check while nothing has left the tree since the scan
  (`_detachedSubtrees` is empty).
- Duplicate memory: a candidate kept its full path as its own `NSData`. It
  now keeps its folder's path, shared by the candidates of one folder, and
  a copy of its name in the collector's `LDNameArena` (released when the
  collector finishes). Building one folder path per directory read instead
  of a path per file also takes work off the scanner workers.

The scanner's per-node layout is unchanged (`/usr`, 522k files: 101 MB RSS
after the scan before and after).

## Results

Headless (`lindirstat-bench`, same tree, logical sizes):

| | Before | After |
| --- | --- | --- |
| Finalize, 4 threads (logical / physical metric) | 0.69 s / 1.0–1.2 s | 0.05–0.15 s / 0.07–0.11 s |
| Finalize, 1 thread | 0.77 s | 0.06–0.12 s |
| `/usr` finalize (522k files, physical) | 0.63–0.76 s | 0.07–0.10 s |
| Main-thread completion work (stats, treemap, Largest Files) | 1.40 s | 0 (0.5–0.8 s on the scanning thread) |
| Stop (after 1 s, ~650k files) to completion block | 0.41 s + 0.56 s on the main thread | 0.39 s, nothing left on the main thread |
| Peak RSS, duplicates off | 208 MB | 207 MB |
| Peak RSS, duplicates on, 4 threads | 547–565 MB | 405–415 MB |
| Peak RSS, duplicates on, 1 thread | 550 MB | 413 MB |
| Duplicate overhead over the plain scan | ~340 MB | ~200 MB |

In the app (`LINDIRSTAT_PROFILE=1`, 4 threads, Xvfb):

| | Before | After |
| --- | --- | --- |
| `-finishAsyncScan` on the main thread | 0.70–0.92 s | 15–25 ms |
| Completion to display | 1.5–1.7 s | 80–100 ms (to 200 ms under heavy load) |
| Stop to display (Stop after 1.5 s) | 2.2 s | 0.5–0.7 s |
| Stop to display, duplicates on (Stop after 2 s) | 1.9 s | 0.67 s |
| Main-thread stalls over 100 ms while hashing duplicates | every 0.5 s, 250–570 ms | none |

The treemap drawn from the scanning thread's pixels is identical to the one
the view renders itself (0 differing pixels in the treemap area of the
screenshots).

## Remaining

- With duplicate detection on, the read phase is about twice as long:
  hashing runs at the same time and the collector's lock is shared by the
  workers.
- A duplicate candidate still costs about 200 bytes (an object with three
  16-byte digests); C structs in per-bucket arrays would halve that.
- Refreshes, metric changes, zoom and resizing still lay out and render the
  treemap on the main thread (0.5 s for a million files); doing that in the
  background needs the tree to be frozen while a render reads it.
