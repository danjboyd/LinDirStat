#import "LDFileNode.h"

@implementation LDFileNode

+ (id)nodeWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size
{
  return [[[self alloc] initWithPath:path kind:kind size:size] autorelease];
}

- (id)initWithPath:(NSString *)path kind:(LDFileNodeKind)kind size:(unsigned long long)size
{
  self = [super init];
  if (self) {
    _path = [path copy];
    _displayName = [[path lastPathComponent] copy];
    if ([_displayName length] == 0) {
      [_displayName release];
      _displayName = [path copy];
    }
    _kind = kind;
    _size = size;
    _allocatedSize = size;
    _aggregateSize = size;
    _fileCount = (kind == LDFileNodeKindDirectory) ? 0 : 1;
    _directoryCount = (kind == LDFileNodeKindDirectory) ? 1 : 0;
    _children = [[NSMutableArray alloc] init];
  }
  return self;
}

- (NSString *)path { return _path; }
- (NSString *)displayName { return _displayName; }
- (LDFileNodeKind)kind { return _kind; }
- (unsigned long long)size { return _size; }
- (unsigned long long)allocatedSize { return _allocatedSize; }
- (void)setAllocatedSize:(unsigned long long)allocatedSize { _allocatedSize = allocatedSize; }
- (unsigned long long)aggregateSize { return _aggregateSize; }
- (NSUInteger)fileCount { return _fileCount; }
- (NSUInteger)directoryCount { return _directoryCount; }
- (NSString *)errorCode { return _errorCode; }
- (LDFileNode *)parent { return _parent; }
- (NSArray *)children { return _children; }

- (void)setErrorCode:(NSString *)errorCode
{
  if (_errorCode != errorCode) {
    [_errorCode release];
    _errorCode = [errorCode copy];
  }
}

- (void)addChild:(LDFileNode *)child
{
  if (!child) {
    return;
  }
  child->_parent = self;
  [_children addObject:child];
}

- (void)recalculateAggregateSize
{
  unsigned long long aggregate = (_kind == LDFileNodeKindDirectory) ? 0 : _size;
  NSUInteger files = (_kind == LDFileNodeKindDirectory) ? 0 : 1;
  NSUInteger directories = (_kind == LDFileNodeKindDirectory) ? 1 : 0;

  NSEnumerator *enumerator = [_children objectEnumerator];
  LDFileNode *child = nil;
  while ((child = [enumerator nextObject])) {
    [child recalculateAggregateSize];
    aggregate += [child aggregateSize];
    files += [child fileCount];
    directories += [child directoryCount];
  }

  _aggregateSize = aggregate;
  _fileCount = files;
  _directoryCount = directories;
}

- (NSComparisonResult)compareByAggregateSizeThenName:(LDFileNode *)other
{
  if (_aggregateSize > [other aggregateSize]) {
    return NSOrderedAscending;
  }
  if (_aggregateSize < [other aggregateSize]) {
    return NSOrderedDescending;
  }
  return [_displayName compare:[other displayName]];
}

- (NSDictionary *)snapshotDictionary
{
  NSMutableArray *childSnapshots = [NSMutableArray array];
  NSEnumerator *enumerator = [_children objectEnumerator];
  LDFileNode *child = nil;
  while ((child = [enumerator nextObject])) {
    [childSnapshots addObject:[child snapshotDictionary]];
  }

  NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
  [snapshot setObject:_path forKey:@"path"];
  [snapshot setObject:_displayName forKey:@"display_name"];
  [snapshot setObject:[NSNumber numberWithInt:_kind] forKey:@"kind"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_size] forKey:@"size"];
  [snapshot setObject:[NSNumber numberWithUnsignedLongLong:_aggregateSize] forKey:@"aggregate_size"];
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
  [_path release];
  [_displayName release];
  [_errorCode release];
  [_children release];
  [super dealloc];
}

@end
