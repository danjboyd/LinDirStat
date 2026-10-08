#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDScanSession.h"

@interface LDScanSessionTests : XCTestCase
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

@end
