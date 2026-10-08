#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDExtensionColor.h"
#import "LDExtensionStats.h"
#import "LDFileNode.h"

@interface LDExtensionColorTests : XCTestCase
@end

@implementation LDExtensionColorTests

- (void)testPaletteMatchesWinDirStatEqualizedColors
{
  // CTreeMap::GetDefaultPalette: DefaultCushionColors through MakeBrightColor(c, 0.6).
  LDRGBColor expected[] = {
    0x6565FF, 0xFF6565, 0x65FF65, 0xE5E500, 0x00E5E5, 0xE500E5,
    0xFFC10A, 0x2C9EFF, 0xFF2C9E, 0x9EFF2C, 0xC10AFF, 0x2CFF9E,
    0xFF0AC1, 0x0AC1FF, 0xFF9E2C, 0x0AFFC1, 0x9E2CFF, 0x999999,
  };
  XCTAssertEqual((NSUInteger)18, [LDExtensionColor paletteCount]);
  NSUInteger i = 0;
  for (i = 0; i < 18; i++) {
    XCTAssertEqual(expected[i], [LDExtensionColor paletteColorAtIndex:i]);
  }
}

- (void)testRanksBeyondPaletteShareLastColor
{
  XCTAssertEqual((NSUInteger)0, [LDExtensionColor paletteIndexForRank:0]);
  XCTAssertEqual((NSUInteger)16, [LDExtensionColor paletteIndexForRank:16]);
  XCTAssertEqual((NSUInteger)17, [LDExtensionColor paletteIndexForRank:17]);
  XCTAssertEqual((NSUInteger)17, [LDExtensionColor paletteIndexForRank:250]);
}

- (void)testExtensionColorsFollowByteRank
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/r" kind:LDFileNodeKindDirectory size:0];
  int i = 0;
  for (i = 0; i < 20; i++) {
    NSString *name = [NSString stringWithFormat:@"file.e%02d", i];
    unsigned long long size = (unsigned long long)(1000 - i);
    [root addChild:[LDFileNode nodeWithName:name kind:LDFileNodeKindFile size:size allocatedSize:size]];
  }
  [root recalculateAggregateSize];

  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root metric:LDSizeMetricPhysical];
  NSDictionary *map = [LDExtensionStats colorIndexMapForSortedStats:stats];

  XCTAssertEqualObjects(@"e00", [[stats objectAtIndex:0] extensionKey]);
  XCTAssertEqualObjects([NSNumber numberWithInt:0], [map objectForKey:@"e00"]);
  XCTAssertEqualObjects([NSNumber numberWithInt:16], [map objectForKey:@"e16"]);
  XCTAssertEqualObjects([NSNumber numberWithInt:17], [map objectForKey:@"e17"]);
  XCTAssertEqualObjects([NSNumber numberWithInt:17], [map objectForKey:@"e19"]);
}

- (void)testExtensionBytesPerMetric
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/r" kind:LDFileNodeKindDirectory size:0];
  [root addChild:[LDFileNode nodeWithName:@"a.log" kind:LDFileNodeKindFile size:10 allocatedSize:4096]];
  [root addChild:[LDFileNode nodeWithName:@"b.log" kind:LDFileNodeKindFile size:20 allocatedSize:4096]];
  [root recalculateAggregateSize];

  LDExtensionStats *logs = [[LDExtensionStats sortedStatsForRootNode:root metric:LDSizeMetricPhysical] objectAtIndex:0];
  XCTAssertEqual((unsigned long long)30, [logs bytesForMetric:LDSizeMetricLogical]);
  XCTAssertEqual((unsigned long long)8192, [logs bytesForMetric:LDSizeMetricPhysical]);
}

@end
