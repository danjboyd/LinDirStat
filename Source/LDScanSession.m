#import "LDScanSession.h"
#import "LDFileNode.h"
#import "LDScanner.h"

@implementation LDScanSession

- (LDScanSessionState)state { return _state; }
- (NSString *)currentPath { return _currentPath; }
- (NSUInteger)skippedCount { return _skippedCount; }
- (NSUInteger)errorCount { return _errorCount; }
- (LDFileNode *)rootNode { return _rootNode; }
- (BOOL)isCanceled { return _canceled; }

- (void)setCurrentPath:(NSString *)currentPath
{
  if (_currentPath != currentPath) {
    [_currentPath release];
    _currentPath = [currentPath copy];
  }
}

- (void)incrementSkippedCount { _skippedCount += 1; }
- (void)incrementErrorCount { _errorCount += 1; }

- (void)setRootNode:(LDFileNode *)rootNode
{
  if (_rootNode != rootNode) {
    [_rootNode release];
    _rootNode = [rootNode retain];
  }
}

- (void)markScanning
{
  _state = LDScanSessionStateScanning;
  _canceled = NO;
  [_startedAt release];
  _startedAt = [[NSDate date] retain];
  [_finishedAt release];
  _finishedAt = nil;
}

- (void)markComplete
{
  _state = _canceled ? LDScanSessionStateCanceled : LDScanSessionStateComplete;
  [_finishedAt release];
  _finishedAt = [[NSDate date] retain];
}

- (void)markFailed
{
  _state = LDScanSessionStateFailed;
  [_finishedAt release];
  _finishedAt = [[NSDate date] retain];
}

- (void)cancel
{
  _canceled = YES;
}

- (void)startAsyncScanPath:(NSString *)path
{
  [_asyncPath release];
  _asyncPath = [path copy];
  _asyncFinished = NO;
  [NSThread detachNewThreadSelector:@selector(runAsyncScan) toTarget:self withObject:nil];
}

- (void)runAsyncScan
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  [scanner scanPath:_asyncPath session:self];
  _asyncFinished = YES;
  [pool release];
}

- (BOOL)waitUntilFinishedBeforeDate:(NSDate *)deadline
{
  while (!_asyncFinished && [[NSDate date] compare:deadline] == NSOrderedAscending) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  return _asyncFinished;
}

- (NSDictionary *)snapshotDictionary
{
  NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
  [snapshot setObject:[NSNumber numberWithInt:_state] forKey:@"state"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:_skippedCount] forKey:@"skipped_count"];
  [snapshot setObject:[NSNumber numberWithUnsignedInteger:_errorCount] forKey:@"error_count"];
  if (_currentPath) {
    [snapshot setObject:_currentPath forKey:@"current_path"];
  }
  if (_rootNode) {
    [snapshot setObject:[_rootNode snapshotDictionary] forKey:@"root"];
  }
  return snapshot;
}

- (void)dealloc
{
  [_currentPath release];
  [_startedAt release];
  [_finishedAt release];
  [_rootNode release];
  [_asyncPath release];
  [super dealloc];
}

@end
