#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDScanOptions.h"
#import "LDScanProgress.h"

@interface LDScanProgressTests : XCTestCase
@end

@implementation LDScanProgressTests

- (void)testRangeIsTheUsedSpaceOfEveryVolume
{
  XCTAssertEqual(300ULL, ([LDScanProgress rangeForUsedBytes:@[@100, @200] excludeMountPoints:YES excludeSymbolicLinks:YES]));
}

- (void)testNoRangeForFoldersOrScansThatCanLeaveTheVolume
{
  XCTAssertEqual(0ULL, ([LDScanProgress rangeForUsedBytes:@[@100, @0] excludeMountPoints:YES excludeSymbolicLinks:YES]));
  XCTAssertEqual(0ULL, ([LDScanProgress rangeForUsedBytes:@[@100] excludeMountPoints:NO excludeSymbolicLinks:YES]));
  XCTAssertEqual(0ULL, ([LDScanProgress rangeForUsedBytes:@[@100] excludeMountPoints:YES excludeSymbolicLinks:NO]));
  XCTAssertEqual(0ULL, ([LDScanProgress rangeForUsedBytes:@[] excludeMountPoints:YES excludeSymbolicLinks:YES]));
}

- (void)testPercentIsCappedAtOneHundred
{
  XCTAssertEqual((NSInteger)0, [LDScanProgress percentForPosition:5 range:0]);
  XCTAssertEqual((NSInteger)42, [LDScanProgress percentForPosition:42 range:100]);
  XCTAssertEqual((NSInteger)100, [LDScanProgress percentForPosition:150 range:100]);
  // No overflow for huge volumes.
  XCTAssertEqual((NSInteger)50, [LDScanProgress percentForPosition:(1ULL << 62) range:(1ULL << 63)]);
}

- (void)testTitlePrefixes
{
  XCTAssertEqualObjects(@"42%", [LDScanProgress titlePrefixForPosition:42 range:100 suspended:NO]);
  XCTAssertEqualObjects(@"42% (Suspended)", [LDScanProgress titlePrefixForPosition:42 range:100 suspended:YES]);
  XCTAssertEqualObjects(@"Scanning", [LDScanProgress titlePrefixForPosition:42 range:0 suspended:NO]);
  XCTAssertEqualObjects(@"Scanning (Suspended)", [LDScanProgress titlePrefixForPosition:42 range:0 suspended:YES]);
}

- (void)testTheRootIsAVolumeAndATemporaryFolderIsNot
{
  XCTAssertTrue([LDScanProgress isVolumeRootPath:@"/"]);
  XCTAssertTrue([LDScanProgress usedBytesOfVolumeAtPath:@"/"] > 0);
  NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"lindirstat-progress-%d", getpid()]];
  [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
  XCTAssertFalse([LDScanProgress isVolumeRootPath:folder]);
  XCTAssertEqual(0ULL, ([LDScanProgress rangeForScanPaths:@[folder] options:nil]));
  XCTAssertFalse([LDScanProgress isVolumeRootPath:[folder stringByAppendingPathComponent:@"missing"]]);
  [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];

  LDScanOptions *options = [[LDScanOptions alloc] init];
  XCTAssertTrue(([LDScanProgress rangeForScanPaths:@[@"/"] options:options]) > 0);
  [options setExcludeMountPoints:NO];
  XCTAssertEqual(0ULL, ([LDScanProgress rangeForScanPaths:@[@"/"] options:options]));
}

@end
