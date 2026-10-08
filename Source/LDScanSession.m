#import "LDScanSession.h"
#import "LDFileNode.h"
#import "LDScanner.h"

#include <dispatch/dispatch.h>

@implementation LDScanSession

- (id)init
{
  self = [super init];
  if (self) {
    _lock = [[NSLock alloc] init];
    _sortMetric = LDSizeMetricPhysical;
    _threadCount = [LDScanner defaultThreadCount];
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
- (NSUInteger)threadCount { return _threadCount; }
- (void)setThreadCount:(NSUInteger)threadCount { _threadCount = threadCount; }

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

- (void)recordFiles:(NSUInteger)files directories:(NSUInteger)directories bytes:(unsigned long long)bytes
{
  __atomic_add_fetch(&_filesScanned, files, __ATOMIC_RELAXED);
  __atomic_add_fetch(&_directoriesScanned, directories, __ATOMIC_RELAXED);
  __atomic_add_fetch(&_bytesScanned, bytes, __ATOMIC_RELAXED);
}

- (NSString *)currentPath
{
  [_lock lock];
  NSString *path = _currentPath;
  [_lock unlock];
  return path;
}

- (void)setCurrentPath:(NSString *)currentPath
{
  NSString *copy = [currentPath copy];
  [_lock lock];
  _currentPath = copy;
  [_lock unlock];
}

- (LDFileNode *)rootNode
{
  [_lock lock];
  LDFileNode *root = _rootNode;
  [_lock unlock];
  return root;
}

- (void)setRootNode:(LDFileNode *)rootNode
{
  // Keep the previous tree alive until after unlocking; freeing a large
  // tree is slow and must not happen while holding the lock.
  __attribute__((objc_precise_lifetime)) LDFileNode *previous = nil;
  [_lock lock];
  previous = _rootNode;
  _rootNode = rootNode;
  [_lock unlock];
}

- (NSTimeInterval)elapsedTime
{
  [_lock lock];
  NSDate *start = _startedAt;
  NSDate *finish = _finishedAt;
  [_lock unlock];
  if (!start) {
    return 0.0;
  }
  return [(finish ? finish : [NSDate date]) timeIntervalSinceDate:start];
}

- (void)setStartedAt:(NSDate *)startedAt finishedAt:(NSDate *)finishedAt
{
  [_lock lock];
  _startedAt = startedAt;
  _finishedAt = finishedAt;
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
  _finishedAt = [NSDate date];
  [_lock unlock];
}

- (void)markFailed
{
  _state = LDScanSessionStateFailed;
  [_lock lock];
  _finishedAt = [NSDate date];
  [_lock unlock];
}

- (void)cancel
{
  __atomic_store_n(&_canceled, YES, __ATOMIC_RELEASE);
}

- (void)startAsyncScanPath:(NSString *)path
{
  [self startAsyncScanPath:path completion:nil];
}

- (void)startAsyncScanPath:(NSString *)path completion:(void (^)(void))completion
{
  _asyncPath = [path copy];
  __atomic_store_n(&_asyncFinished, NO, __ATOMIC_RELEASE);
  // The blocks keep the session alive until the scan and completion are done.
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @autoreleasepool {
      LDScanner *scanner = [[LDScanner alloc] init];
      [scanner setSortMetric:_sortMetric];
      [scanner setThreadCount:_threadCount];
      [scanner scanPath:_asyncPath session:self];
    }
    __atomic_store_n(&_asyncFinished, YES, __ATOMIC_RELEASE);
    if (completion) {
      dispatch_async(dispatch_get_main_queue(), completion);
    }
  });
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

@end
