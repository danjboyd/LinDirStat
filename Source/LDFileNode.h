#import <Foundation/Foundation.h>

typedef enum {
  LDFileNodeKindFile = 0,
  LDFileNodeKindDirectory = 1,
  LDFileNodeKindSymlink = 2,
  LDFileNodeKindSpecial = 3
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
  uint8_t _ownsName;
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
// Made on demand from the stored bytes (UTF-8, or Latin-1 if they are not
// valid UTF-8).
- (NSString *)displayName;
// NUL-terminated name bytes as read from the filesystem.
- (const char *)nameBytes;
- (LDFileNodeKind)kind;
- (BOOL)isLeaf;

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
// errorNumber is the errno for LDFileNodeErrorStatFailed.
- (void)setError:(LDFileNodeError)error errorNumber:(int)errorNumber;
// A stable string for the error ("stat_failed:<reason>", "mount_point", ...).
- (NSString *)errorCode;
- (BOOL)isHardLinkDuplicate;
- (BOOL)isMountPoint;

- (LDFileNode *)parent;
- (NSArray *)children;
- (void)addChild:(LDFileNode *)child;
- (BOOL)isAncestorOf:(LDFileNode *)node;
- (NSUInteger)depth;

- (void)recalculateAggregateSize;
// Sorts children (recursively) by descending size for the metric, then name
// bytes. Views read -children directly, so this must run once after a scan and
// again when the size metric changes. It also trims children arrays to size.
- (void)sortChildrenByMetric:(LDSizeMetric)metric;

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
}

// Keeps storage the subtree depends on (the scan's name arenas) alive.
- (void)setOwnedStorage:(id)storage;

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
