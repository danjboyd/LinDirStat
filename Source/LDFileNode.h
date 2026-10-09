#import <Foundation/Foundation.h>

typedef enum {
  LDFileNodeKindFile = 0,
  LDFileNodeKindDirectory = 1,
  LDFileNodeKindSymlink = 2,
  LDFileNodeKindSpecial = 3,
  // WinDirStat's "<Free Space>" and "<Unknown>" pseudo-files under a volume
  // (Options › Show Free Space / Show Unknown). They have a physical size
  // only and are not files: see -isSpaceItem.
  LDFileNodeKindFreeSpace = 4,
  LDFileNodeKindUnknown = 5
} LDFileNodeKind;

// WinDirStat defaults to physical (allocated) sizes and offers logical sizes
// as an option ("Use Logical Size").
typedef enum {
  LDSizeMetricPhysical = 0,
  LDSizeMetricLogical = 1
} LDSizeMetric;

typedef enum {
  LDFileNodeErrorNone = 0,
  LDFileNodeErrorStatFailed,
  LDFileNodeErrorHardLinkDuplicate,
  LDFileNodeErrorSpecialFile,
  LDFileNodeErrorMountPoint,
  LDFileNodeErrorDirectoryCycle,
  LDFileNodeErrorDirectoryUnreadable
} LDFileNodeError;

@class LDNameArena;

// One scanned filesystem entry. Scans can hold millions of these, so the
// layout follows WinDirStat's CItem: files carry only their own data and
// directory-only state lives in LDDirectoryNode. Names are stored as bytes,
// usually in an LDNameArena kept alive by the tree's root.
//
// A node must not outlive the root of its tree: parent pointers are
// non-owning and arena names belong to the root.
@interface LDFileNode : NSObject
{
  const char *_name;
  __unsafe_unretained LDFileNode *_parent;
  NSString *_extensionKey;
  unsigned long long _size;
  unsigned long long _allocatedSize;
  int64_t _modificationTime;
  uint32_t _mode;
  uint8_t _kind;
  uint8_t _error;
  uint8_t _flags;
  uint8_t _errorNumber;
}

// Creates a node that remembers its full path. Used for scan roots and tests.
// Directory kinds return an LDDirectoryNode.
+ (id)nodeWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size;

// Creates a node that stores only its name; its path is derived from its parent.
+ (id)nodeWithName:(NSString *)name kind:(LDFileNodeKind)kind size:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize;

// Creates a node whose name is copied into arena, which must outlive it.
+ (id)nodeWithNameBytes:(const char *)bytes
                 length:(size_t)length
                  arena:(LDNameArena *)arena
                   kind:(LDFileNodeKind)kind
                   size:(unsigned long long)size
          allocatedSize:(unsigned long long)allocatedSize;

- (NSString *)path;
// The full path as filesystem bytes (no terminating NUL), built from the
// stored name bytes. Unlike -path it is exact for names that are not valid
// UTF-8, so anything that touches the filesystem must use it.
- (NSData *)pathData;
// Made on demand from the stored bytes (UTF-8, or Latin-1 if they are not
// valid UTF-8).
- (NSString *)displayName;
// NUL-terminated name bytes as read from the filesystem.
- (const char *)nameBytes;
- (LDFileNodeKind)kind;
- (BOOL)isLeaf;
// YES only for the synthetic root of a multi-root scan (LDComputerNode).
- (BOOL)isComputer;
// YES for the <Free Space> and <Unknown> pseudo-files. They have no path on
// disk, count as no file, and no command, file list or statistic uses them.
- (BOOL)isSpaceItem;
// A detached <Free Space> or <Unknown> node of the given physical size.
+ (LDFileNode *)spaceItemWithKind:(LDFileNodeKind)kind allocatedSize:(unsigned long long)allocatedSize;

// Logical size (st_size) of this node alone.
- (unsigned long long)size;
// Physical size (st_blocks * 512) of this node alone.
- (unsigned long long)allocatedSize;
- (void)setAllocatedSize:(unsigned long long)allocatedSize;
- (void)setSize:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize;
- (unsigned long long)sizeForMetric:(LDSizeMetric)metric;

// Logical subtree size.
- (unsigned long long)aggregateSize;
// Physical subtree size.
- (unsigned long long)aggregateAllocatedSize;
- (unsigned long long)aggregateSizeForMetric:(LDSizeMetric)metric;

- (NSUInteger)fileCount;
- (NSUInteger)directoryCount;

// Seconds since 1970. For directories, aggregateModificationTime is the newest
// time in the subtree, matching WinDirStat's "Last Change" column.
- (NSTimeInterval)modificationTime;
- (NSTimeInterval)aggregateModificationTime;
- (void)setModificationTime:(NSTimeInterval)modificationTime;
- (unsigned int)mode;
- (void)setMode:(unsigned int)mode;

// Lowercased extension used for grouping and colors ("<none>" if absent).
// Cached; the scanner sets interned instances so equal keys share storage.
- (NSString *)extensionKey;
- (void)setExtensionKey:(NSString *)extensionKey;

- (LDFileNodeError)error;
// errorNumber is the errno for LDFileNodeErrorStatFailed and
// LDFileNodeErrorDirectoryUnreadable.
- (void)setError:(LDFileNodeError)error errorNumber:(int)errorNumber;
- (int)errorNumber;
// A stable string for the error ("stat_failed:<reason>", "mount_point", ...).
- (NSString *)errorCode;
- (BOOL)isHardLinkDuplicate;
- (BOOL)isMountPoint;
// WinDirStat's ITF_HARDLINK: a link of a file with several links in the
// tree, counted under "<Hardlinks>" (see LDHardLinks.h). Its aggregate sizes
// are 0, so it adds nothing to its folders; -size and -allocatedSize keep
// what the scan gave it.
- (BOOL)isHardLink;
- (void)setHardLink:(BOOL)flag;

- (LDFileNode *)parent;
- (NSArray *)children;
- (void)addChild:(LDFileNode *)child;
- (BOOL)isAncestorOf:(LDFileNode *)node;
- (NSUInteger)depth;

- (void)recalculateAggregateSize;
// After an edit below this node: recomputes the totals of this node and of
// each ancestor from their direct children, and re-sorts their children by
// metric. Main thread only, once the scan is finished.
- (void)updateTotalsUpwardSortedByMetric:(LDSizeMetric)metric;
// Sorts children (recursively) by descending size for the metric, then name
// bytes. Views read -children directly, so this must run once after a scan and
// again when the size metric changes. It also trims children arrays to size.
- (void)sortChildrenByMetric:(LDSizeMetric)metric;
// As above, but the replaced children arrays are added to retired instead of
// being released, so a thread that read them during a live scan can finish
// with them (see -[LDDirectoryNode publishChildren:]).
- (void)sortChildrenByMetric:(LDSizeMetric)metric retiring:(NSMutableArray *)retired;
// -recalculateAggregateSize then -sortChildrenByMetric:retiring: in one
// bottom-up pass, with independent subtrees finished concurrently. Same
// result; this is what a scan runs once its tree is complete.
- (void)finishTreeSortedByMetric:(LDSizeMetric)metric retiring:(NSMutableArray *)retired;

// YES while this directory or something below it is still being read.
- (BOOL)isScanPending;
// Directory reads still to finish in this subtree (WinDirStat's read jobs).
- (NSUInteger)pendingScanCount;
// WinDirStat's time spent (now in LDScanClock milliseconds): seconds since
// the first read job was queued while pending, then the time the reads took.
// 0 for files and for folders not scanned live.
- (NSUInteger)scanSecondsAt:(uint64_t)now;
// Milliseconds since the last progress below this pending folder; 0 when
// it is not pending.
- (uint64_t)millisecondsSinceScanActivityAt:(uint64_t)now;

- (NSComparisonResult)compareByAggregateSizeThenName:(LDFileNode *)other;
- (NSDictionary *)snapshotDictionary;

@end

@interface LDDirectoryNode : LDFileNode
{
  NSString *_storedPath;
  id _children;
  id _ownedStorage;
  unsigned long long _aggregateSize;
  unsigned long long _aggregateAllocatedSize;
  int64_t _aggregateModificationTime;
  uint32_t _fileCount;
  uint32_t _directoryCount;
  uint32_t _pendingScans;
  // LDScanClock stamps in what was padding: when the first read job was
  // queued (seconds), and while pending the last progress below this node
  // (10 ms steps), replaced by the read's duration in seconds once done.
  uint16_t _scanStarted;
  uint16_t _scanActivity;
}

// Keeps storage the subtree depends on (the scan's name arenas and hard-link
// table) alive.
- (void)setOwnedStorage:(id)storage;
- (id)ownedStorage;

// Live scans. A directory's children are published once, as a complete
// array that is never mutated, so the main thread can read the tree while
// workers are still adding to it.
- (void)publishChildren:(NSArray *)children;
// Adds a finished directory read's direct files to this node and every
// ancestor, so totals grow while the scan runs. Thread-safe.
- (void)addLiveFiles:(NSUInteger)files
         directories:(NSUInteger)directories
                size:(unsigned long long)size
       allocatedSize:(unsigned long long)allocatedSize
    modificationTime:(int64_t)modificationTime;
// Pending-read accounting for -isScanPending. A directory starts with one
// pending read (its own); queueing a subdirectory adds one, and when a
// directory's count reaches zero its parent's count drops by one.
- (void)beginPendingScans:(NSUInteger)count;
- (void)finishPendingScan;
- (void)clearPendingScans;
// Records progress (now, in LDScanClock milliseconds) on this node and every
// pending ancestor, for the pacmen's sleep test. Thread-safe.
- (void)noteScanActivityAt:(uint64_t)now;

// Tree edits after a scan (main thread only). Totals are not updated; call
// -updateTotalsUpwardSortedByMetric: on this directory afterwards.
- (void)removeChild:(LDFileNode *)child;
- (void)replaceChild:(LDFileNode *)child withNode:(LDFileNode *)replacement;
// Recomputes this directory's totals from its direct children only.
- (void)recalculateOwnTotals;

@end

// The synthetic root of a scan of several paths ("This Computer", WinDirStat's
// MyComputer item). Its children are full-path roots, so their paths do not
// depend on it: its -path is its display name and its -pathData is empty.
@interface LDComputerNode : LDDirectoryNode
+ (LDComputerNode *)computerNode;
@end

// Bump allocator for node names. Not thread-safe: each scan worker uses its
// own arena, and the scan root keeps all of them alive.
@interface LDNameArena : NSObject
{
  NSMutableArray *_chunks;
  char *_cursor;
  size_t _remaining;
}

// Copies length bytes plus a terminating NUL and returns the copy.
- (const char *)copyBytes:(const char *)bytes length:(size_t)length;

@end
