#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDScanSession.h"
#import "LDScanOptions.h"

#include <unistd.h>

@interface LDScanSessionTests : XCTestCase
{
  NSString *_temporaryRoot;
}
@end

@implementation LDScanSessionTests

- (NSString *)fixturePath
{
  return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Tests/Fixtures/basic-tree"];
}

- (void)testStateTransitionsAndSnapshot
{
  LDScanSession *session = [[LDScanSession alloc] init];
  [session markScanning];
  [session setCurrentPath:@"/tmp/example"];
  [session incrementSkippedCount];
  [session markComplete];

  NSDictionary *snapshot = [session snapshotDictionary];

  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertEqualObjects(@"/tmp/example", [snapshot objectForKey:@"current_path"]);
  XCTAssertEqualObjects([NSNumber numberWithUnsignedInteger:1], [snapshot objectForKey:@"skipped_count"]);
}

- (void)testAsyncScanCompletes
{
  LDScanSession *session = [[LDScanSession alloc] init];
  [session startAsyncScanPath:[self fixturePath]];

  BOOL finished = [session waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]];

  XCTAssertTrue(finished);
  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertEqual((unsigned long long)40, [[session rootNode] aggregateSize]);
}

- (void)testCompletionRunsOnMainThread
{
  LDScanSession *session = [[LDScanSession alloc] init];
  __block BOOL called = NO;
  __block BOOL onMainThread = NO;
  [session startAsyncScanPath:[self fixturePath] completion:^{
    called = YES;
    onMainThread = [NSThread isMainThread];
  }];

  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (!called && [[NSDate date] compare:deadline] == NSOrderedAscending) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }

  XCTAssertTrue(called);
  XCTAssertTrue(onMainThread);
  XCTAssertEqual((unsigned long long)40, [[session rootNode] aggregateSize]);
}

- (void)testCancelStopsALargeScan
{
  LDScanSession *session = [[LDScanSession alloc] init];
  [session startAsyncScanPath:@"/usr"];
  [NSThread sleepForTimeInterval:0.05];
  [session cancel];

  XCTAssertTrue([session waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]]);
  XCTAssertEqual(LDScanSessionStateCanceled, [session state]);
  XCTAssertNotNil([session rootNode]);
}

- (NSString *)temporaryRoot
{
  if (!_temporaryRoot) {
    NSString *name = [NSString stringWithFormat:@"lindirstat-session-tests-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]];
    _temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:_temporaryRoot withIntermediateDirectories:YES attributes:nil error:NULL];
  }
  return _temporaryRoot;
}

- (void)tearDown
{
  if (_temporaryRoot) {
    [[NSFileManager defaultManager] removeItemAtPath:_temporaryRoot error:NULL];
    _temporaryRoot = nil;
  }
  [super tearDown];
}

// A root holding count folders, each with one 100-byte file.
- (NSString *)makeTreeNamed:(NSString *)name folders:(NSUInteger)count
{
  NSString *root = [[self temporaryRoot] stringByAppendingPathComponent:name];
  for (NSUInteger i = 0; i < count; i++) {
    NSString *folder = [root stringByAppendingPathComponent:[NSString stringWithFormat:@"d%lu", (unsigned long)i]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSMutableData dataWithLength:100] writeToFile:[folder stringByAppendingPathComponent:@"f.bin"] atomically:NO];
  }
  return root;
}

- (void)spinRunLoopFor:(NSTimeInterval)seconds
{
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (void)testSuspendedScanReadsNothingUntilResumed
{
  NSString *root = [self makeTreeNamed:@"tree" folders:40];
  LDScanSession *session = [[LDScanSession alloc] init];
  [session suspend];
  XCTAssertTrue([session isSuspended]);
  [session startAsyncScanPath:root completion:nil];
  [self spinRunLoopFor:0.3];

  XCTAssertFalse([session isFinished]);
  XCTAssertEqual((NSUInteger)0, [session filesScanned]);
  XCTAssertTrue([[session rootNode] isScanPending]);

  [session resume];
  XCTAssertFalse([session isSuspended]);
  XCTAssertTrue([session waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]]);
  XCTAssertEqual(LDScanSessionStateComplete, [session state]);
  XCTAssertEqual((NSUInteger)40, [session filesScanned]);
  XCTAssertEqual((unsigned long long)4000, [[session rootNode] aggregateSize]);
}

- (void)testCancelWakesSuspendedWorkers
{
  NSString *root = [self makeTreeNamed:@"tree" folders:40];
  LDScanSession *session = [[LDScanSession alloc] init];
  [session suspend];
  [session startAsyncScanPath:root completion:nil];
  [self spinRunLoopFor:0.1];
  [session cancel];

  XCTAssertTrue([session waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]]);
  XCTAssertEqual(LDScanSessionStateCanceled, [session state]);
  XCTAssertFalse([[session rootNode] isScanPending]);
}

- (void)testElapsedTimeExcludesSuspendedTime
{
  LDScanSession *session = [[LDScanSession alloc] init];
  [session markScanning];
  [session suspend];
  [NSThread sleepForTimeInterval:0.3];
  NSTimeInterval whileSuspended = [session elapsedTime];
  [NSThread sleepForTimeInterval:0.1];
  XCTAssertEqualWithAccuracy(whileSuspended, [session elapsedTime], 0.02);
  [session resume];
  [NSThread sleepForTimeInterval:0.1];
  [session markComplete];

  NSTimeInterval elapsed = [session elapsedTime];
  XCTAssertTrue(elapsed >= 0.09);
  XCTAssertTrue(elapsed < 0.3);
}

- (void)testMultiRootScanPublishesTheComputerNodeFirst
{
  NSString *a = [self makeTreeNamed:@"a" folders:10];
  NSString *b = [self makeTreeNamed:@"b" folders:5];
  LDScanSession *session = [[LDScanSession alloc] init];
  [session suspend];
  [session startAsyncScanPaths:[NSArray arrayWithObjects:a, b, nil] completion:nil];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (![[session rootNode] isComputer] && [[NSDate date] compare:deadline] == NSOrderedAscending) {
    [self spinRunLoopFor:0.01];
  }

  LDFileNode *computer = [session rootNode];
  XCTAssertTrue([computer isComputer]);
  XCTAssertTrue([computer isScanPending]);
  XCTAssertEqual((NSUInteger)2, [[computer children] count]);
  for (LDFileNode *root in [computer children]) {
    XCTAssertTrue([root isScanPending]);
    XCTAssertEqual(computer, [root parent]);
  }

  [session resume];
  XCTAssertTrue([session waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]]);
  XCTAssertEqual(computer, [session rootNode]);
  XCTAssertFalse([computer isScanPending]);
  XCTAssertEqual((unsigned long long)1500, [computer aggregateSize]);
  XCTAssertEqual((NSUInteger)15, [session filesScanned]);
}

- (void)testAsyncScansUseTheSessionOptions
{
  NSString *root = [self makeTreeNamed:@"tree" folders:3];
  [[NSMutableData dataWithLength:50] writeToFile:[root stringByAppendingPathComponent:@"skip.log"] atomically:NO];
  LDScanOptions *options = [[LDScanOptions alloc] init];
  [options setExcludedFilePatterns:[NSArray arrayWithObject:@"*.log"]];
  [options setExcludedFolderPatterns:[NSArray arrayWithObject:[root stringByAppendingPathComponent:@"d0"]]];
  [options setThreadCount:2];

  LDScanSession *session = [[LDScanSession alloc] init];
  [session setScanOptions:options];
  [options setExcludedFilePatterns:nil];
  XCTAssertEqual((NSUInteger)2, [session threadCount]);
  [session startAsyncScanPath:root completion:nil];
  XCTAssertTrue([session waitUntilFinishedBeforeDate:[NSDate dateWithTimeIntervalSinceNow:5.0]]);
  XCTAssertEqual((unsigned long long)200, [[session rootNode] aggregateSize]);
}

@end
