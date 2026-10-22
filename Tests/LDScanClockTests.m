#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDScanClock.h"
#import "LDScanner.h"
#import "LDScanSession.h"

#include <unistd.h>

@interface LDScanClockTests : XCTestCase
@end

@implementation LDScanClockTests

- (void)testStampsMeasureAcrossWraparound
{
  uint64_t start = 65535ULL * 1000 + 400;
  uint16_t stamp = LDScanClockSecondsStamp(start);
  XCTAssertEqual((NSUInteger)0, LDScanClockSecondsSince(stamp, start));
  XCTAssertEqual((NSUInteger)3, LDScanClockSecondsSince(stamp, start + 3000));
  uint16_t activity = LDScanClockActivityStamp(start);
  XCTAssertEqual(800ULL, LDScanClockMillisecondsSince(activity, start + 800));
  XCTAssertEqual(655350ULL, LDScanClockMillisecondsSince(activity, start + 655350));
}

- (void)testPacmanSleepsAfterWinDirStatsThreshold
{
  XCTAssertFalse(LDPacmanIsAsleep(750, 10000, NO));
  XCTAssertTrue(LDPacmanIsAsleep(760, 10000, NO));
  // Suspended pacmen freeze instead, and a resume restarts the wait.
  XCTAssertFalse(LDPacmanIsAsleep(5000, 10000, YES));
  XCTAssertFalse(LDPacmanIsAsleep(5000, 200, NO));
}

- (void)testDurationsUseWinDirStatsFormat
{
  XCTAssertEqualObjects(@"0:00", LDFormatScanDuration(0));
  XCTAssertEqualObjects(@"1:05", LDFormatScanDuration(65));
  XCTAssertEqualObjects(@"59:59", LDFormatScanDuration(3599));
  XCTAssertEqualObjects(@"1:00:00", LDFormatScanDuration(3600));
  XCTAssertEqualObjects(@"2:03:04", LDFormatScanDuration(7384));
}

- (void)testClockIsMonotonic
{
  uint64_t first = LDScanClockMilliseconds();
  XCTAssertTrue(LDScanClockMilliseconds() >= first);
}

- (void)testPendingFolderTracksTimeAndActivity
{
  LDDirectoryNode *root = [LDFileNode nodeWithPath:@"/r" kind:LDFileNodeKindDirectory size:0];
  LDDirectoryNode *child = [LDFileNode nodeWithName:@"c" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [root publishChildren:@[child]];
  [root beginPendingScans:1];
  [child beginPendingScans:1];
  [root beginPendingScans:1];
  uint64_t now = LDScanClockMilliseconds();
  uint64_t scanNow = LDScanClockActiveMilliseconds();
  XCTAssertTrue([root scanSecondsAt:scanNow + 5000] >= 4);
  XCTAssertTrue([child millisecondsSinceScanActivityAt:now + 2000] >= 1900);

  // Progress below the root keeps both awake.
  [child noteScanActivityAt:now + 2000];
  XCTAssertTrue([root millisecondsSinceScanActivityAt:now + 2000] <= 10);
  XCTAssertTrue([child millisecondsSinceScanActivityAt:now + 2100] <= 110);

  // Done: the time spent stays, and there is nothing to sleep on.
  [child finishPendingScan];
  XCTAssertFalse([child isScanPending]);
  XCTAssertEqual((uint64_t)0, [child millisecondsSinceScanActivityAt:now + 9000]);
  XCTAssertTrue([child scanSecondsAt:scanNow + 99000] <= 1);
  XCTAssertTrue([root isScanPending]);
}

- (void)testScannedFoldersAreDoneWithTheirTimeKept
{
  NSString *fixture = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Tests/Fixtures/basic-tree"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:fixture]) {
    fixture = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Fixtures/basic-tree"];
  }
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [[[LDScanner alloc] init] scanPath:fixture session:session];
  XCTAssertTrue([root directoryCount] > 1);
  uint64_t now = LDScanClockMilliseconds();
  XCTAssertFalse([root isScanPending]);
  XCTAssertTrue([root scanSecondsAt:LDScanClockActiveMilliseconds() + 60000] <= 1);
  XCTAssertEqual((uint64_t)0, [root millisecondsSinceScanActivityAt:now]);
}

- (void)testFilesAndUnscannedFoldersSpendNoTime
{
  LDFileNode *file = [LDFileNode nodeWithName:@"f" kind:LDFileNodeKindFile size:1 allocatedSize:1];
  LDFileNode *folder = [LDFileNode nodeWithName:@"d" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  XCTAssertEqual((NSUInteger)0, [file scanSecondsAt:LDScanClockMilliseconds()]);
  XCTAssertEqual((NSUInteger)0, [folder scanSecondsAt:LDScanClockMilliseconds()]);
  XCTAssertEqual((uint64_t)0, [folder millisecondsSinceScanActivityAt:LDScanClockMilliseconds()]);
}

// WinDirStat 2.6 (e451d346): time suspended does not count as time spent.
- (void)testScanTimeStandsStillWhileSuspended
{
  uint64_t base = LDScanClockMilliseconds();
  uint64_t start = LDScanClockActiveMillisecondsAt(base);
  LDScanClockSuspendAt(base + 2000);
  LDScanClockSuspendAt(base + 3000);
  XCTAssertEqual(start + 2000, LDScanClockActiveMillisecondsAt(base + 9000));
  LDScanClockResumeAt(base + 10000);
  LDScanClockResumeAt(base + 11000);
  XCTAssertEqual(start + 2000, LDScanClockActiveMillisecondsAt(base + 10000));
  XCTAssertEqual(start + 4000, LDScanClockActiveMillisecondsAt(base + 12000));
  // Undo the 8 s pause: suspended at scan time t, resuming at time t leaves
  // no paused time at all.
  LDScanClockSuspendAt(base + 12000);
  LDScanClockResumeAt(LDScanClockActiveMillisecondsAt(base + 12000));
  XCTAssertEqual(base + 12000, LDScanClockActiveMillisecondsAt(base + 12000));
}

- (void)testSuspendedSessionPausesFolderTime
{
  LDScanSession *session = [[LDScanSession alloc] init];
  [session suspend];
  uint64_t frozen = LDScanClockActiveMilliseconds();
  usleep(50000);
  XCTAssertEqual(frozen, LDScanClockActiveMilliseconds());
  [session resume];
  usleep(50000);
  XCTAssertTrue(LDScanClockActiveMilliseconds() > frozen);

  // Stopping a suspended scan lets scan time run again.
  [session suspend];
  frozen = LDScanClockActiveMilliseconds();
  [session cancel];
  usleep(50000);
  XCTAssertTrue(LDScanClockActiveMilliseconds() > frozen);
}

@end
