#import "LDFileNode.h"
#import "LDExtensionStats.h"
#import "LDScanClock.h"

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

// A file (not directory) node that remembers its full path: scan roots that
// are files, and nodes built by tests.
@interface LDPathFileNode : LDFileNode
{
  NSString *_storedPath;
}
@end

@interface LDFileNode ()
- (id)initWithNodeKind:(LDFileNodeKind)kind;
- (char)appendPathToData:(NSMutableData *)data separator:(char)separator;
- (void)setNameBytes:(const char *)bytes length:(size_t)length arena:(LDNameArena *)arena;
- (void)setStoredPath:(NSString *)path;
@end

@interface LDDirectoryNode ()
- (void)sortOwnChildrenByMetric:(LDSizeMetric)metric;
@end

enum {
  LDFileNodeFlagOwnsName = 1 << 0,
  LDFileNodeFlagHardLink = 1 << 1,
  // A stored path whose descendants are joined with '\\' (a Windows tree
  // loaded from a WinDirStat CSV).
  LDFileNodeFlagBackslashPaths = 1 << 2
};

static Class LDClassForKind(LDFileNodeKind kind)
{
  return kind == LDFileNodeKindDirectory ? [LDDirectoryNode class] : [LDFileNode class];
}

@implementation LDFileNode

+ (id)nodeWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size
{
  Class nodeClass = kind == LDFileNodeKindDirectory ? [LDDirectoryNode class] : [LDPathFileNode class];
  LDFileNode *node = [[nodeClass alloc] initWithNodeKind:kind];
  NSString *name = [path lastPathComponent];
  if ([name length] == 0) {
    name = path;
  }
  const char *bytes = [name UTF8String];
  [node setNameBytes:bytes length:strlen(bytes) arena:nil];
  [node setStoredPath:path];
  [node setSize:size allocatedSize:size];
  return node;
}

+ (id)nodeWithName:(NSString *)name kind:(LDFileNodeKind)kind size:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize
{
  const char *bytes = [name UTF8String];
  return [self nodeWithNameBytes:bytes length:strlen(bytes) arena:nil kind:kind size:size allocatedSize:allocatedSize];
}

+ (id)nodeWithNameBytes:(const char *)bytes
                 length:(size_t)length
                  arena:(LDNameArena *)arena
                   kind:(LDFileNodeKind)kind
                   size:(unsigned long long)size
          allocatedSize:(unsigned long long)allocatedSize
{
  // Subclasses other than LDDirectoryNode (pseudo-items) keep their class.
  Class nodeClass = (self == [LDFileNode class] || self == [LDDirectoryNode class]) ? LDClassForKind(kind) : self;
  LDFileNode *node = [[nodeClass alloc] initWithNodeKind:kind];
  [node setNameBytes:bytes length:length arena:arena];
  [node setSize:size allocatedSize:allocatedSize];
  return node;
}

+ (LDFileNode *)spaceItemWithKind:(LDFileNodeKind)kind allocatedSize:(unsigned long long)allocatedSize
{
  // Names as WinDirStat's IDS_FREESPACE_ITEM and IDS_UNKNOWN_ITEM.
  NSString *name = kind == LDFileNodeKindFreeSpace ? @"<Free Space>" : @"<Unknown>";
  return [self nodeWithName:name kind:kind size:0 allocatedSize:allocatedSize];
}

- (id)initWithNodeKind:(LDFileNodeKind)kind
{
  self = [super init];
  if (self) {
    _kind = (uint8_t)kind;
  }
  return self;
}

- (void)dealloc
{
  if (_flags & LDFileNodeFlagOwnsName) {
    free((void *)_name);
  }
}

- (void)setNameBytes:(const char *)bytes length:(size_t)length arena:(LDNameArena *)arena
{
  if (arena) {
    _name = [arena copyBytes:bytes length:length];
    _flags &= ~LDFileNodeFlagOwnsName;
  } else {
    char *copy = malloc(length + 1);
    memcpy(copy, bytes, length);
    copy[length] = '\0';
    _name = copy;
    _flags |= LDFileNodeFlagOwnsName;
  }
}

- (void)setStoredPath:(NSString *)path
{
  (void)path;
}

- (NSString *)storedPath
{
  return nil;
}

- (void)setUsesBackslashPaths:(BOOL)flag
{
  if (flag) {
    _flags |= LDFileNodeFlagBackslashPaths;
  } else {
    _flags &= ~LDFileNodeFlagBackslashPaths;
  }
}

- (char)pathSeparator
{
  for (LDFileNode *node = self; node; node = node->_parent) {
    if ([node storedPath]) {
      return (node->_flags & LDFileNodeFlagBackslashPaths) ? '\\' : '/';
    }
  }
  return '/';
}

// The path, and the separator its descendants are joined with.
- (NSString *)pathWithSeparator:(char *)separator
{
  NSString *stored = [self storedPath];
  if (stored) {
    *separator = (_flags & LDFileNodeFlagBackslashPaths) ? '\\' : '/';
    return stored;
  }
  if (_parent) {
    NSString *parentPath = [_parent pathWithSeparator:separator];
    if (*separator == '/') {
      return [parentPath stringByAppendingPathComponent:[self displayName]];
    }
    return [parentPath hasSuffix:@"\\"] ? [parentPath stringByAppendingString:[self displayName]]
                                         : [NSString stringWithFormat:@"%@\\%@", parentPath, [self displayName]];
  }
  *separator = '/';
  return [self displayName];
}

- (NSString *)path
{
  char separator = '/';
  return [self pathWithSeparator:&separator];
}

- (char)appendPathToData:(NSMutableData *)data separator:(char)separator
{
  NSString *stored = [self storedPath];
  if (stored) {
    const char *bytes = [stored fileSystemRepresentation];
    [data appendBytes:bytes length:strlen(bytes)];
    return (_flags & LDFileNodeFlagBackslashPaths) ? '\\' : '/';
  }
  if (_parent) {
    separator = [_parent appendPathToData:data separator:separator];
    if ([data length] == 0 || ((const char *)[data bytes])[[data length] - 1] != separator) {
      [data appendBytes:&separator length:1];
    }
  }
  [data appendBytes:_name length:strlen(_name)];
  return separator;
}

- (void)appendPathToData:(NSMutableData *)data
{
  [self appendPathToData:data separator:'/'];
}

- (NSData *)pathData
{
  NSMutableData *data = [NSMutableData data];
  [self appendPathToData:data];
  return data;
}

- (NSString *)displayName
{
  size_t length = strlen(_name);
  NSString *name = [[NSString alloc] initWithBytes:_name length:length encoding:NSUTF8StringEncoding];
  if (!name) {
    name = [[NSString alloc] initWithBytes:_name length:length encoding:NSISOLatin1StringEncoding];
  }
  return name;
}

- (const char *)nameBytes { return _name; }
- (LDFileNodeKind)kind { return (LDFileNodeKind)_kind; }
- (BOOL)isLeaf { return YES; }
- (BOOL)isComputer { return NO; }
- (BOOL)isSpaceItem { return _kind == LDFileNodeKindFreeSpace || _kind == LDFileNodeKindUnknown; }
- (unsigned long long)size { return _size; }
- (unsigned long long)allocatedSize { return _allocatedSize; }
- (unsigned long long)aggregateSize { return (_flags & LDFileNodeFlagHardLink) ? 0 : _size; }
- (unsigned long long)aggregateAllocatedSize { return (_flags & LDFileNodeFlagHardLink) ? 0 : _allocatedSize; }
- (NSUInteger)fileCount { return [self isSpaceItem] ? 0 : 1; }
- (NSUInteger)directoryCount { return 0; }
- (NSTimeInterval)modificationTime { return (NSTimeInterval)_modificationTime; }
- (NSTimeInterval)aggregateModificationTime { return (NSTimeInterval)_modificationTime; }
- (unsigned int)mode { return _mode; }
- (LDFileNode *)parent { return _parent; }
- (NSArray *)children { return [NSArray array]; }
- (LDFileNodeError)error { return (LDFileNodeError)_error; }

- (void)setAllocatedSize:(unsigned long long)allocatedSize
{
  _allocatedSize = allocatedSize;
}

- (void)setSize:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize
{
  _size = size;
  [self setAllocatedSize:allocatedSize];
}

- (unsigned long long)sizeForMetric:(LDSizeMetric)metric
{
  return metric == LDSizeMetricLogical ? _size : _allocatedSize;
}

- (unsigned long long)aggregateSizeForMetric:(LDSizeMetric)metric
{
  return metric == LDSizeMetricLogical ? [self aggregateSize] : [self aggregateAllocatedSize];
}

- (double)fractionOfParentForMetric:(LDSizeMetric)metric
{
  if (!_parent) {
    return 1.0;
  }
  unsigned long long parentBytes = [_parent aggregateSizeForMetric:metric];
  return parentBytes ? (double)[self aggregateSizeForMetric:metric] / (double)parentBytes : 0.0;
}

- (double)fractionOfRootForMetric:(LDSizeMetric)metric
{
  if (!_parent) {
    return 1.0;
  }
  LDFileNode *root = _parent;
  while (root->_parent) {
    root = root->_parent;
  }
  unsigned long long rootBytes = [root aggregateSizeForMetric:metric];
  return rootBytes ? (double)[self aggregateSizeForMetric:metric] / (double)rootBytes : 0.0;
}

- (void)setModificationTime:(NSTimeInterval)modificationTime
{
  _modificationTime = (int64_t)modificationTime;
}

- (void)setMode:(unsigned int)mode { _mode = mode; }

- (NSString *)extensionKey
{
  if (!_extensionKey) {
    _extensionKey = [LDExtensionStats extensionKeyForFilename:[self displayName]];
  }
  return _extensionKey;
}

- (void)setExtensionKey:(NSString *)extensionKey
{
  _extensionKey = extensionKey;
}

- (void)setError:(LDFileNodeError)error errorNumber:(int)errorNumber
{
  _error = (uint8_t)error;
  _errorNumber = (uint8_t)errorNumber;
}

- (int)errorNumber
{
  return _errorNumber;
}

- (NSString *)errorCode
{
  switch ((LDFileNodeError)_error) {
    case LDFileNodeErrorNone: return nil;
    case LDFileNodeErrorStatFailed: return [NSString stringWithFormat:@"stat_failed:%s", strerror(_errorNumber)];
    case LDFileNodeErrorHardLinkDuplicate: return @"hard_link_duplicate";
    case LDFileNodeErrorSpecialFile: return @"special_file";
    case LDFileNodeErrorMountPoint: return @"mount_point";
    case LDFileNodeErrorDirectoryCycle: return @"directory_cycle";
    case LDFileNodeErrorDirectoryUnreadable: return @"directory_unreadable";
  }
  return nil;
}

- (BOOL)isHardLinkDuplicate { return _error == LDFileNodeErrorHardLinkDuplicate; }
- (BOOL)isMountPoint { return _error == LDFileNodeErrorMountPoint; }
- (BOOL)isHardLink { return (_flags & LDFileNodeFlagHardLink) != 0; }

- (void)setHardLink:(BOOL)flag
{
  if (flag) {
    _flags |= LDFileNodeFlagHardLink;
  } else {
    _flags &= ~LDFileNodeFlagHardLink;
  }
}

- (void)addChild:(LDFileNode *)child
{
  (void)child;
  [NSException raise:NSInvalidArgumentException format:@"%s is not a directory", _name];
}

- (BOOL)isAncestorOf:(LDFileNode *)node
{
  LDFileNode *cursor = node;
  while (cursor) {
    if (cursor == self) {
      return YES;
    }
    cursor = cursor->_parent;
  }
  return NO;
}

- (NSUInteger)depth
{
  NSUInteger depth = 0;
  LDFileNode *cursor = _parent;
  while (cursor) {
    depth++;
    cursor = cursor->_parent;
  }
  return depth;
}

- (void)recalculateAggregateSize
{
}

- (void)sortChildrenByMetric:(LDSizeMetric)metric
{
  [self sortChildrenByMetric:metric retiring:nil];
}

- (void)sortChildrenByMetric:(LDSizeMetric)metric retiring:(NSMutableArray *)retired
{
  (void)metric;
  (void)retired;
}

- (void)finishTreeSortedByMetric:(LDSizeMetric)metric retiring:(NSMutableArray *)retired
{
  (void)metric;
  (void)retired;
}

- (BOOL)isScanPending
{
  return NO;
}

- (NSUInteger)pendingScanCount
{
  return 0;
}

- (NSUInteger)scanSecondsAt:(uint64_t)now
{
  (void)now;
  return 0;
}

- (uint64_t)millisecondsSinceScanActivityAt:(uint64_t)now
{
  (void)now;
  return 0;
}

- (void)updateTotalsUpwardSortedByMetric:(LDSizeMetric)metric
{
  LDFileNode *cursor = self;
  while (cursor) {
    if ([cursor isKindOfClass:[LDDirectoryNode class]]) {
      LDDirectoryNode *directory = (LDDirectoryNode *)cursor;
      [directory recalculateOwnTotals];
      [directory sortOwnChildrenByMetric:metric];
    }
    cursor = cursor->_parent;
  }
}

static NSComparisonResult LDCompareNodesBySize(id left, id right, void *context)
{
  LDSizeMetric metric = (LDSizeMetric)(intptr_t)context;
  unsigned long long leftSize = [(LDFileNode *)left aggregateSizeForMetric:metric];
  unsigned long long rightSize = [(LDFileNode *)right aggregateSizeForMetric:metric];
  if (leftSize > rightSize) {
    return NSOrderedAscending;
  }
  if (leftSize < rightSize) {
    return NSOrderedDescending;
  }
  // Byte order of UTF-8 is code point order, without making strings.
  int order = strcmp(((LDFileNode *)left)->_name, ((LDFileNode *)right)->_name);
  return order < 0 ? NSOrderedAscending : (order > 0 ? NSOrderedDescending : NSOrderedSame);
}

- (NSComparisonResult)compareByAggregateSizeThenName:(LDFileNode *)other
{
  return LDCompareNodesBySize(self, other, (void *)(intptr_t)LDSizeMetricLogical);
}

- (NSDictionary *)snapshotDictionary
{
  NSMutableArray *childSnapshots = [NSMutableArray array];
  NSEnumerator *enumerator = [[self children] objectEnumerator];
  LDFileNode *child = nil;
  while ((child = [enumerator nextObject])) {
    [childSnapshots addObject:[child snapshotDictionary]];
  }

  NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
  [snapshot setObject:[self path] forKey:@"path"];
  [snapshot setObject:[self displayName] forKey:@"display_name"];
  [snapshot setObject:[NSNumber numberWithInt:_kind] forKey:@"kind"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_size] forKey:@"size"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_allocatedSize] forKey:@"allocated_size"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:[self aggregateSize]] forKey:@"aggregate_size"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:[self aggregateAllocatedSize]] forKey:@"aggregate_allocated_size"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:[self fileCount]] forKey:@"file_count"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:[self directoryCount]] forKey:@"directory_count"];
  NSString *errorCode = [self errorCode];
  if (errorCode) {
    [snapshot setObject:errorCode forKey:@"error_code"];
  }
  [snapshot setObject:childSnapshots forKey:@"children"];
  return snapshot;
}

@end

@implementation LDPathFileNode

- (void)setStoredPath:(NSString *)path { _storedPath = [path copy]; }
- (NSString *)storedPath { return _storedPath; }

@end

@implementation LDDirectoryNode

- (void)setStoredPath:(NSString *)path { _storedPath = [path copy]; }
- (NSString *)storedPath { return _storedPath; }
- (void)setOwnedStorage:(id)storage { _ownedStorage = storage; }
- (id)ownedStorage { return _ownedStorage; }
- (BOOL)isScanPending { return __atomic_load_n(&_pendingScans, __ATOMIC_RELAXED) > 0; }
- (NSUInteger)pendingScanCount { return __atomic_load_n(&_pendingScans, __ATOMIC_RELAXED); }

- (BOOL)isLeaf { return [_children count] == 0; }
- (NSArray *)children { return _children ? _children : [NSArray array]; }
- (unsigned long long)aggregateSize { return _aggregateSize; }
- (unsigned long long)aggregateAllocatedSize { return _aggregateAllocatedSize; }
- (NSUInteger)fileCount { return _fileCount; }
- (NSUInteger)directoryCount { return _directoryCount; }
- (NSTimeInterval)aggregateModificationTime { return (NSTimeInterval)_aggregateModificationTime; }

- (void)setModificationTime:(NSTimeInterval)modificationTime
{
  [super setModificationTime:modificationTime];
  _aggregateModificationTime = _modificationTime;
}

- (void)addChild:(LDFileNode *)child
{
  if (!child) {
    return;
  }
  if (![_children isKindOfClass:[NSMutableArray class]]) {
    _children = _children ? [_children mutableCopy] : [[NSMutableArray alloc] init];
  }
  child->_parent = self;
  [_children addObject:child];
}

- (void)publishChildren:(NSArray *)children
{
  for (LDFileNode *child in children) {
    child->_parent = self;
  }
  // Parents and names must be visible before the array is.
  __atomic_thread_fence(__ATOMIC_RELEASE);
  _children = [children count] > 0 ? children : nil;
}

static void LDAtomicMax64(int64_t *target, int64_t value)
{
  int64_t current = __atomic_load_n(target, __ATOMIC_RELAXED);
  while (value > current
         && !__atomic_compare_exchange_n(target, &current, value, YES, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
  }
}

- (void)addLiveFiles:(NSUInteger)files
         directories:(NSUInteger)directories
                size:(unsigned long long)size
       allocatedSize:(unsigned long long)allocatedSize
    modificationTime:(int64_t)modificationTime
{
  LDFileNode *cursor = self;
  while ([cursor isKindOfClass:[LDDirectoryNode class]]) {
    LDDirectoryNode *directory = (LDDirectoryNode *)cursor;
    __atomic_add_fetch(&directory->_aggregateSize, size, __ATOMIC_RELAXED);
    __atomic_add_fetch(&directory->_aggregateAllocatedSize, allocatedSize, __ATOMIC_RELAXED);
    __atomic_add_fetch(&directory->_fileCount, (uint32_t)files, __ATOMIC_RELAXED);
    __atomic_add_fetch(&directory->_directoryCount, (uint32_t)directories, __ATOMIC_RELAXED);
    LDAtomicMax64(&directory->_aggregateModificationTime, modificationTime);
    cursor = cursor->_parent;
  }
}

- (void)beginPendingScans:(NSUInteger)count
{
  // WinDirStat's m_tstart: set when the first read job is added.
  if (__atomic_fetch_add(&_pendingScans, (uint32_t)count, __ATOMIC_RELAXED) == 0 && count > 0) {
    __atomic_store_n(&_scanStarted, LDScanClockSecondsStamp(LDScanClockActiveMilliseconds()), __ATOMIC_RELAXED);
    __atomic_store_n(&_scanActivity, LDScanClockActivityStamp(LDScanClockMilliseconds()), __ATOMIC_RELAXED);
  }
}

- (void)finishPendingScan
{
  if (__atomic_sub_fetch(&_pendingScans, 1, __ATOMIC_ACQ_REL) == 0) {
    uint16_t started = __atomic_load_n(&_scanStarted, __ATOMIC_RELAXED);
    __atomic_store_n(&_scanActivity, (uint16_t)LDScanClockSecondsSince(started, LDScanClockActiveMilliseconds()), __ATOMIC_RELAXED);
    if ([_parent isKindOfClass:[LDDirectoryNode class]]) {
      [(LDDirectoryNode *)_parent finishPendingScan];
    }
  }
}

- (void)noteScanActivityAt:(uint64_t)now
{
  uint16_t stamp = LDScanClockActivityStamp(now);
  LDFileNode *cursor = self;
  while ([cursor isKindOfClass:[LDDirectoryNode class]]) {
    LDDirectoryNode *directory = (LDDirectoryNode *)cursor;
    if (__atomic_load_n(&directory->_pendingScans, __ATOMIC_RELAXED) == 0) {
      break;
    }
    // Skip the store when it would not change, so busy ancestors' cache
    // lines are not written by every worker.
    if (__atomic_load_n(&directory->_scanActivity, __ATOMIC_RELAXED) != stamp) {
      __atomic_store_n(&directory->_scanActivity, stamp, __ATOMIC_RELAXED);
    }
    cursor = cursor->_parent;
  }
}

- (NSUInteger)scanSecondsAt:(uint64_t)now
{
  if ([self isScanPending]) {
    return LDScanClockSecondsSince(__atomic_load_n(&_scanStarted, __ATOMIC_RELAXED), now);
  }
  return __atomic_load_n(&_scanActivity, __ATOMIC_RELAXED);
}

- (uint64_t)millisecondsSinceScanActivityAt:(uint64_t)now
{
  if (![self isScanPending]) {
    return 0;
  }
  return LDScanClockMillisecondsSince(__atomic_load_n(&_scanActivity, __ATOMIC_RELAXED), now);
}

- (void)clearPendingScans
{
  __atomic_store_n(&_pendingScans, 0, __ATOMIC_RELAXED);
}

- (void)removeChild:(LDFileNode *)child
{
  NSMutableArray *children = [[self children] mutableCopy];
  NSUInteger index = [children indexOfObjectIdenticalTo:child];
  if (index == NSNotFound) {
    return;
  }
  [children removeObjectAtIndex:index];
  child->_parent = nil;
  _children = [children count] > 0 ? [children copy] : nil;
}

- (void)replaceChild:(LDFileNode *)child withNode:(LDFileNode *)replacement
{
  NSMutableArray *children = [[self children] mutableCopy];
  NSUInteger index = [children indexOfObjectIdenticalTo:child];
  if (index == NSNotFound || !replacement) {
    return;
  }
  [children replaceObjectAtIndex:index withObject:replacement];
  child->_parent = nil;
  replacement->_parent = self;
  _children = [children copy];
}

- (void)recalculateOwnTotals
{
  unsigned long long aggregate = 0;
  unsigned long long aggregateAllocated = 0;
  int64_t newest = _modificationTime;
  NSUInteger files = 0;
  NSUInteger directories = 1;
  for (LDFileNode *child in [self children]) {
    aggregate += [child aggregateSize];
    aggregateAllocated += [child aggregateAllocatedSize];
    files += [child fileCount];
    directories += [child directoryCount];
    newest = MAX(newest, (int64_t)[child aggregateModificationTime]);
  }
  _aggregateSize = aggregate;
  _aggregateAllocatedSize = aggregateAllocated;
  _aggregateModificationTime = newest;
  _fileCount = (uint32_t)files;
  _directoryCount = (uint32_t)directories;
}

- (void)sortOwnChildrenByMetric:(LDSizeMetric)metric
{
  if ([_children count] > 1) {
    _children = [_children sortedArrayUsingFunction:LDCompareNodesBySize context:(void *)(intptr_t)metric];
  }
}

- (void)recalculateAggregateSize
{
  unsigned long long aggregate = 0;
  unsigned long long aggregateAllocated = 0;
  int64_t newest = _modificationTime;
  NSUInteger files = 0;
  NSUInteger directories = 1;

  NSUInteger count = [_children count];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    LDFileNode *child = [_children objectAtIndex:i];
    [child recalculateAggregateSize];
    aggregate += [child aggregateSize];
    aggregateAllocated += [child aggregateAllocatedSize];
    files += [child fileCount];
    directories += [child directoryCount];
    int64_t childNewest = (int64_t)[child aggregateModificationTime];
    if (childNewest > newest) {
      newest = childNewest;
    }
  }

  _aggregateSize = aggregate;
  _aggregateAllocatedSize = aggregateAllocated;
  _aggregateModificationTime = newest;
  _fileCount = (uint32_t)files;
  _directoryCount = (uint32_t)directories;
  _pendingScans = 0;
}

- (void)sortChildrenByMetric:(LDSizeMetric)metric retiring:(NSMutableArray *)retired
{
  if (_children && retired) {
    [retired addObject:_children];
  }
  if ([_children count] == 0) {
    _children = nil;
    return;
  }
  // An immutable sorted copy is allocated at its exact size, dropping the
  // spare capacity the mutable array grew while scanning.
  _children = [_children sortedArrayUsingFunction:LDCompareNodesBySize context:(void *)(intptr_t)metric];
  NSUInteger count = [_children count];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    [[_children objectAtIndex:i] sortChildrenByMetric:metric retiring:retired];
  }
}

typedef struct {
  unsigned long long size;
  __unsafe_unretained LDFileNode *node;
} LDSortEntry;

// LDCompareNodesBySize on precomputed sizes.
static int LDCompareSortEntries(const void *leftEntry, const void *rightEntry)
{
  const LDSortEntry *left = leftEntry;
  const LDSortEntry *right = rightEntry;
  if (left->size != right->size) {
    return left->size > right->size ? -1 : 1;
  }
  return strcmp(left->node->_name, right->node->_name);
}

// One directory's part of -finishTreeSortedByMetric:retiring:, once its
// subdirectories are finished: its totals from its children, then its
// children sorted into an exact-size array. The replaced array is retired.
- (void)finishOwnChildrenByMetric:(LDSizeMetric)metric retiring:(NSMutableArray *)retired
{
  NSArray *children = _children;
  NSUInteger count = [children count];
  if (children && retired) {
    [retired addObject:children];
  }
  unsigned long long aggregate = 0;
  unsigned long long aggregateAllocated = 0;
  int64_t newest = _modificationTime;
  NSUInteger files = 0;
  NSUInteger directories = 1;
  LDSortEntry inlineEntries[64];
  LDSortEntry *entries = count <= 64 ? inlineEntries : malloc(count * sizeof(LDSortEntry));
  NSUInteger index = 0;
  for (LDFileNode *child in children) {
    aggregate += [child aggregateSize];
    aggregateAllocated += [child aggregateAllocatedSize];
    files += [child fileCount];
    directories += [child directoryCount];
    int64_t childNewest = (int64_t)[child aggregateModificationTime];
    if (childNewest > newest) {
      newest = childNewest;
    }
    entries[index].size = metric == LDSizeMetricLogical ? [child aggregateSize] : [child aggregateAllocatedSize];
    entries[index].node = child;
    index++;
  }
  _aggregateSize = aggregate;
  _aggregateAllocatedSize = aggregateAllocated;
  _aggregateModificationTime = newest;
  _fileCount = (uint32_t)files;
  _directoryCount = (uint32_t)directories;
  _pendingScans = 0;

  if (count == 0) {
    _children = nil;
  } else {
    qsort(entries, count, sizeof(LDSortEntry), LDCompareSortEntries);
    __unsafe_unretained id *sorted = (__unsafe_unretained id *)malloc(count * sizeof(id));
    for (index = 0; index < count; index++) {
      sorted[index] = entries[index].node;
    }
    _children = [[NSArray alloc] initWithObjects:sorted count:count];
    free(sorted);
  }
  if (entries != inlineEntries) {
    free(entries);
  }
}

// Finishes directory's subtree on the calling thread, children first.
static void LDFinishSubtree(LDDirectoryNode *directory, LDSizeMetric metric, NSMutableArray *retired)
{
  Class directoryClass = [LDDirectoryNode class];
  for (LDFileNode *child in directory->_children) {
    if ([child isKindOfClass:directoryClass]) {
      LDFinishSubtree((LDDirectoryNode *)child, metric, retired);
    }
  }
  [directory finishOwnChildrenByMetric:metric retiring:retired];
}

// Enough independent subtrees to keep every core busy despite uneven sizes.
static const NSUInteger LDFinishParallelUnits = 256;
static const NSUInteger LDFinishMaximumSplitDepth = 6;

- (void)finishTreeSortedByMetric:(LDSizeMetric)metric retiring:(NSMutableArray *)retired
{
  // Split the top of the tree level by level into subtrees finished in
  // parallel; the directories above them are finished afterwards, deepest
  // first.
  Class directoryClass = [LDDirectoryNode class];
  NSMutableArray *upper = [NSMutableArray array];
  NSMutableArray *level = [NSMutableArray arrayWithObject:self];
  NSUInteger depth = 0;
  while ([level count] > 0 && [level count] < LDFinishParallelUnits && depth < LDFinishMaximumSplitDepth) {
    NSMutableArray *next = [NSMutableArray array];
    for (LDDirectoryNode *directory in level) {
      for (LDFileNode *child in directory->_children) {
        if ([child isKindOfClass:directoryClass]) {
          [next addObject:child];
        }
      }
    }
    [upper addObjectsFromArray:level];
    level = next;
    depth++;
  }

  NSUInteger unitCount = [level count];
  NSArray *units = level;
  pthread_mutex_t retireLock = PTHREAD_MUTEX_INITIALIZER;
  pthread_mutex_t *lock = &retireLock;
  dispatch_apply(unitCount, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    @autoreleasepool {
      NSMutableArray *local = retired ? [NSMutableArray array] : nil;
      LDFinishSubtree([units objectAtIndex:index], metric, local);
      if ([local count] > 0) {
        pthread_mutex_lock(lock);
        [retired addObjectsFromArray:local];
        pthread_mutex_unlock(lock);
      }
    }
  });
  pthread_mutex_destroy(&retireLock);

  for (LDDirectoryNode *directory in [upper reverseObjectEnumerator]) {
    [directory finishOwnChildrenByMetric:metric retiring:retired];
  }
}

@end

static const char LDComputerNodeName[] = "This Computer";

@implementation LDComputerNode

+ (LDComputerNode *)computerNode
{
  LDComputerNode *node = [[LDComputerNode alloc] initWithNodeKind:LDFileNodeKindDirectory];
  [node setNameBytes:LDComputerNodeName length:strlen(LDComputerNodeName) arena:nil];
  return node;
}

- (BOOL)isComputer { return YES; }
- (NSString *)path { return [self displayName]; }
- (NSData *)pathData { return [NSData data]; }
- (void)appendPathToData:(NSMutableData *)data { (void)data; }
- (char)appendPathToData:(NSMutableData *)data separator:(char)separator { (void)data; return separator; }

@end

// Chunks are large enough that per-name overhead is negligible.
static const size_t LDNameArenaChunkSize = 64 * 1024;

@implementation LDNameArena

- (id)init
{
  self = [super init];
  if (self) {
    _chunks = [[NSMutableArray alloc] init];
  }
  return self;
}

- (const char *)copyBytes:(const char *)bytes length:(size_t)length
{
  size_t needed = length + 1;
  if (needed > _remaining) {
    size_t chunkSize = MAX(LDNameArenaChunkSize, needed);
    NSMutableData *chunk = [NSMutableData dataWithLength:chunkSize];
    [_chunks addObject:chunk];
    _cursor = [chunk mutableBytes];
    _remaining = chunkSize;
  }
  char *copy = _cursor;
  memcpy(copy, bytes, length);
  copy[length] = '\0';
  _cursor += needed;
  _remaining -= needed;
  return copy;
}

@end
