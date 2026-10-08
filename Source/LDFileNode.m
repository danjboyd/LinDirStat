#import "LDFileNode.h"
#import "LDExtensionStats.h"

@implementation LDFileNode

+ (id)nodeWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size
{
  return [[[self alloc] initWithPath:path kind:kind size:size] autorelease];
}

+ (id)nodeWithName:(NSString *)name kind:(LDFileNodeKind)kind size:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize
{
  LDFileNode *node = [[[self alloc] initWithName:name storedPath:nil kind:kind] autorelease];
  [node setSize:size allocatedSize:allocatedSize];
  return node;
}

- (id)initWithName:(NSString *)name storedPath:(NSString *)storedPath kind:(LDFileNodeKind)kind
{
  self = [super init];
  if (self) {
    _name = [name copy];
    _storedPath = [storedPath copy];
    _kind = kind;
    _fileCount = (kind == LDFileNodeKindDirectory) ? 0 : 1;
    _directoryCount = (kind == LDFileNodeKindDirectory) ? 1 : 0;
    if (kind == LDFileNodeKindDirectory) {
      _children = [[NSMutableArray alloc] init];
    }
  }
  return self;
}

- (id)initWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size
{
  NSString *name = [path lastPathComponent];
  if ([name length] == 0) {
    name = path;
  }
  self = [self initWithName:name storedPath:path kind:kind];
  if (self) {
    [self setSize:size allocatedSize:size];
  }
  return self;
}

- (NSString *)path
{
  if (_storedPath) {
    return _storedPath;
  }
  if (_parent) {
    return [[_parent path] stringByAppendingPathComponent:_name];
  }
  return _name;
}

- (NSString *)displayName { return _name; }
- (LDFileNodeKind)kind { return _kind; }
- (BOOL)isLeaf { return [_children count] == 0; }
- (unsigned long long)size { return _size; }
- (unsigned long long)allocatedSize { return _allocatedSize; }
- (unsigned long long)aggregateSize { return _aggregateSize; }
- (unsigned long long)aggregateAllocatedSize { return _aggregateAllocatedSize; }
- (NSUInteger)fileCount { return _fileCount; }
- (NSUInteger)directoryCount { return _directoryCount; }
- (NSTimeInterval)modificationTime { return _modificationTime; }
- (NSTimeInterval)aggregateModificationTime { return _aggregateModificationTime; }
- (unsigned int)mode { return _mode; }
- (NSString *)errorCode { return _errorCode; }
- (LDFileNode *)parent { return _parent; }
- (NSArray *)children { return _children ? _children : [NSArray array]; }

- (void)setAllocatedSize:(unsigned long long)allocatedSize
{
  _allocatedSize = allocatedSize;
  _aggregateAllocatedSize = allocatedSize;
}

- (void)setSize:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize
{
  _size = size;
  _aggregateSize = size;
  [self setAllocatedSize:allocatedSize];
}

- (unsigned long long)sizeForMetric:(LDSizeMetric)metric
{
  return metric == LDSizeMetricLogical ? _size : _allocatedSize;
}

- (unsigned long long)aggregateSizeForMetric:(LDSizeMetric)metric
{
  return metric == LDSizeMetricLogical ? _aggregateSize : _aggregateAllocatedSize;
}

- (void)setModificationTime:(NSTimeInterval)modificationTime
{
  _modificationTime = modificationTime;
  _aggregateModificationTime = modificationTime;
}

- (void)setMode:(unsigned int)mode { _mode = mode; }

- (NSString *)extensionKey
{
  if (!_extensionKey) {
    _extensionKey = [[LDExtensionStats extensionKeyForFilename:_name] retain];
  }
  return _extensionKey;
}

- (void)setExtensionKey:(NSString *)extensionKey
{
  if (_extensionKey != extensionKey) {
    [_extensionKey release];
    _extensionKey = [extensionKey retain];
  }
}

- (void)setErrorCode:(NSString *)errorCode
{
  if (_errorCode != errorCode) {
    [_errorCode release];
    _errorCode = [errorCode copy];
  }
}

- (BOOL)isHardLinkDuplicate
{
  return [_errorCode isEqualToString:@"hard_link_duplicate"];
}

- (BOOL)isMountPoint
{
  return [_errorCode isEqualToString:@"mount_point"];
}

- (void)addChild:(LDFileNode *)child
{
  if (!child) {
    return;
  }
  if (!_children) {
    _children = [[NSMutableArray alloc] init];
  }
  child->_parent = self;
  [_children addObject:child];
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
  BOOL directory = (_kind == LDFileNodeKindDirectory);
  unsigned long long aggregate = directory ? 0 : _size;
  unsigned long long aggregateAllocated = directory ? 0 : _allocatedSize;
  NSTimeInterval newest = _modificationTime;
  NSUInteger files = directory ? 0 : 1;
  NSUInteger directories = directory ? 1 : 0;

  NSUInteger count = [_children count];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    LDFileNode *child = [_children objectAtIndex:i];
    [child recalculateAggregateSize];
    aggregate += child->_aggregateSize;
    aggregateAllocated += child->_aggregateAllocatedSize;
    files += child->_fileCount;
    directories += child->_directoryCount;
    if (child->_aggregateModificationTime > newest) {
      newest = child->_aggregateModificationTime;
    }
  }

  _aggregateSize = aggregate;
  _aggregateAllocatedSize = aggregateAllocated;
  _aggregateModificationTime = newest;
  _fileCount = files;
  _directoryCount = directories;
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
  return [[left displayName] compare:[right displayName]];
}

- (void)sortChildrenByMetric:(LDSizeMetric)metric
{
  if ([_children count] == 0) {
    return;
  }
  [_children sortUsingFunction:LDCompareNodesBySize context:(void *)(intptr_t)metric];
  NSUInteger count = [_children count];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    [[_children objectAtIndex:i] sortChildrenByMetric:metric];
  }
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
  [snapshot setObject:_name forKey:@"display_name"];
  [snapshot setObject:[NSNumber numberWithInt:_kind] forKey:@"kind"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_size] forKey:@"size"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_allocatedSize] forKey:@"allocated_size"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_aggregateSize] forKey:@"aggregate_size"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_aggregateAllocatedSize] forKey:@"aggregate_allocated_size"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:_fileCount] forKey:@"file_count"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:_directoryCount] forKey:@"directory_count"];
  if (_errorCode) {
    [snapshot setObject:_errorCode forKey:@"error_code"];
  }
  [snapshot setObject:childSnapshots forKey:@"children"];
  return snapshot;
}

- (void)dealloc
{
  [_name release];
  [_storedPath release];
  [_errorCode release];
  [_extensionKey release];
  [_children release];
  [super dealloc];
}

@end
