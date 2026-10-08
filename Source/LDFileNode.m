#import "LDFileNode.h"
#import "LDExtensionStats.h"

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
- (void)setNameBytes:(const char *)bytes length:(size_t)length arena:(LDNameArena *)arena;
- (void)setStoredPath:(NSString *)path;
@end

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
  LDFileNode *node = [[LDClassForKind(kind) alloc] initWithNodeKind:kind];
  [node setNameBytes:bytes length:length arena:arena];
  [node setSize:size allocatedSize:allocatedSize];
  return node;
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
  if (_ownsName) {
    free((void *)_name);
  }
}

- (void)setNameBytes:(const char *)bytes length:(size_t)length arena:(LDNameArena *)arena
{
  if (arena) {
    _name = [arena copyBytes:bytes length:length];
    _ownsName = NO;
  } else {
    char *copy = malloc(length + 1);
    memcpy(copy, bytes, length);
    copy[length] = '\0';
    _name = copy;
    _ownsName = YES;
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

- (NSString *)path
{
  NSString *stored = [self storedPath];
  if (stored) {
    return stored;
  }
  if (_parent) {
    return [[_parent path] stringByAppendingPathComponent:[self displayName]];
  }
  return [self displayName];
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
- (unsigned long long)size { return _size; }
- (unsigned long long)allocatedSize { return _allocatedSize; }
- (unsigned long long)aggregateSize { return _size; }
- (unsigned long long)aggregateAllocatedSize { return _allocatedSize; }
- (NSUInteger)fileCount { return 1; }
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
  (void)metric;
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
}

- (void)sortChildrenByMetric:(LDSizeMetric)metric
{
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
    [[_children objectAtIndex:i] sortChildrenByMetric:metric];
  }
}

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
