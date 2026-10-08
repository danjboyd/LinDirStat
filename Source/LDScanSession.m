#import "LDScanSession.h"
#import "LDFileNode.h"
#import "LDScanner.h"

@implementation LDScanSession

- (id)init
{
  self = [super init];
  if (self) {
    _lock = [[NSLock alloc] init];
    _sortMetric = LDSizeMetricPhysical;
  }
  return self;
}

- (LDScanSessionState)state { return _state; }
- (NSUInteger)skippedCount { return __atomic_load_n(&_skippedCount, __ATOMIC_RELAXED); }
- (NSUInteger)errorCount { return __atomic_load_n(&_errorCount, __ATOMIC_RELAXED); }
- (NSUInteger)filesScanned { return __atomic_load_n(&_filesScanned, __ATOMIC_RELAXED); }
- (NSUInteger)directoriesScanned { return __atomic_load_n(&_directoriesScanned, __ATOMIC_RELAXED); }
- (unsigned long long)bytesScanned { return __atomic_load_n(&_bytesScanned, __ATOMIC_RELAXED); }
- (BOOL)isCanceled { return __atomic_load_n(&_canceled, __ATOMIC_ACQUIRE); }
- (BOOL)isFinished { return __atomic_load_n(&_asyncFinished, __ATOMIC_ACQUIRE); }
- (LDSizeMetric)sortMetric { return _sortMetric; }
- (void)setSortMetric:(LDSizeMetric)sortMetric { _sortMetric = sortMetric; }

- (void)incrementSkippedCount { __atomic_add_fetch(&_skippedCount, 1, __ATOMIC_RELAXED); }
- (void)incrementErrorCount { __atomic_add_fetch(&_errorCount, 1, __ATOMIC_RELAXED); }

- (void)recordFileWithBytes:(unsigned long long)bytes
{
  __atomic_add_fetch(&_filesScanned, 1, __ATOMIC_RELAXED);
  __atomic_add_fetch(&_bytesScanned, bytes, __ATOMIC_RELAXED);
}

- (void)recordDirectory
{
  __atomic_add_fetch(&_directoriesScanned, 1, __ATOMIC_RELAXED);
}

- (NSString *)currentPath
{
  [_lock lock];
  NSString *path = [[_currentPath retain] autorelease];
  [_lock unlock];
  return path;
}

- (void)setCurrentPath:(NSString *)currentPath
{
  NSString *copy = [currentPath copy];
  [_lock lock];
  NSString *old = _currentPath;
  _currentPath = copy;
  [_lock unlock];
  [old release];
}

- (LDFileNode *)rootNode
{
  [_lock lock];
  LDFileNode *root = [[_rootNode retain] autorelease];
  [_lock unlock];
  return root;
}

- (void)setRootNode:(LDFileNode *)rootNode
{
  [rootNode retain];
  [_lock lock];
  LDFileNode *old = _rootNode;
  _rootNode = rootNode;
  [_lock unlock];
  [old release];
}

- (NSTimeInterval)elapsedTime
{
  [_lock lock];
  NSDate *start = [[_startedAt retain] autorelease];
  NSDate *finish = [[_finishedAt retain] autorelease];
  [_lock unlock];
  if (!start) {
    return 0.0;
  }
  return [(finish ? finish : [NSDate date]) timeIntervalSinceDate:start];
}

- (void)setStartedAt:(NSDate *)startedAt finishedAt:(NSDate *)finishedAt
{
  [_lock lock];
  [_startedAt release];
  _startedAt = [startedAt retain];
  [_finishedAt release];
  _finishedAt = [finishedAt retain];
  [_lock unlock];
}

- (void)markScanning
{
  _state = LDScanSessionStateScanning;
  [self setStartedAt:[NSDate date] finishedAt:nil];
}

- (void)markComplete
{
  _state = [self isCanceled] ? LDScanSessionStateCanceled : LDScanSessionStateComplete;
  [_lock lock];
  [_finishedAt release];
  _finishedAt = [[NSDate date] retain];
  [_lock unlock];
}

- (void)markFailed
{
  _state = LDScanSessionStateFailed;
  [_lock lock];
  [_finishedAt release];
  _finishedAt = [[NSDate date] retain];
  [_lock unlock];
}

- (void)cancel
{
  __atomic_store_n(&_canceled, YES, __ATOMIC_RELEASE);
}

- (void)startAsyncScanPath:(NSString *)path
{
  [_asyncPath release];
  _asyncPath = [path copy];
  __atomic_store_n(&_asyncFinished, NO, __ATOMIC_RELEASE);
  [self retain];
  [NSThread detachNewThreadSelector:@selector(runAsyncScan) toTarget:self withObject:nil];
}

- (void)runAsyncScan
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  [scanner setSortMetric:_sortMetric];
  [scanner scanPath:_asyncPath session:self];
  __atomic_store_n(&_asyncFinished, YES, __ATOMIC_RELEASE);
  [pool release];
  [self release];
}

- (BOOL)waitUntilFinishedBeforeDate:(NSDate *)deadline
{
  while (![self isFinished] && [[NSDate date] compare:deadline] == NSOrderedAscending) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  return [self isFinished];
}

- (NSDictionary *)snapshotDictionary
{
  NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
  [snapshot setObject:[NSNumber numberWithInt:_state] forKey:@"state"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:[self skippedCount]] forKey:@"skipped_count"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:[self errorCount]] forKey:@"error_count"];
  NSString *currentPath = [self currentPath];
  if (currentPath) {
    [snapshot setObject:currentPath forKey:@"current_path"];
  }
  LDFileNode *root = [self rootNode];
  if (root) {
    [snapshot setObject:[root snapshotDictionary] forKey:@"root"];
  }
  return snapshot;
}

- (void)dealloc
{
  [_lock release];
  [_currentPath release];
  [_startedAt release];
  [_finishedAt release];
  [_rootNode release];
  [_asyncPath release];
  [super dealloc];
}

@end
