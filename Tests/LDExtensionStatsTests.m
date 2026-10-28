#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDExtensionStats.h"

@interface LDExtensionStatsTests : XCTestCase
@end

@implementation LDExtensionStatsTests

- (void)testExtensionKeysMatchWinDirStatStyleCases
{
  XCTAssertEqualObjects(@"txt", [LDExtensionStats extensionKeyForFilename:@"README.TXT"]);
  XCTAssertEqualObjects(@"<none>", [LDExtensionStats extensionKeyForFilename:@"Makefile"]);
  XCTAssertEqualObjects(@"<none>", [LDExtensionStats extensionKeyForFilename:@".profile"]);
  XCTAssertEqualObjects(@"gz", [LDExtensionStats extensionKeyForFilename:@"archive.tar.gz"]);
}

- (void)testCollectsAndSortsExtensionStats
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/tmp/root" kind:LDFileNodeKindDirectory size:0];
  [root addChild:[LDFileNode nodeWithPath:@"/tmp/root/a.txt" kind:LDFileNodeKindFile size:10]];
  [root addChild:[LDFileNode nodeWithPath:@"/tmp/root/b.TXT" kind:LDFileNodeKindFile size:15]];
  [root addChild:[LDFileNode nodeWithPath:@"/tmp/root/blob" kind:LDFileNodeKindFile size:40]];
  [root recalculateAggregateSize];

  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root];
  LDExtensionStats *first = [stats objectAtIndex:0];
  LDExtensionStats *second = [stats objectAtIndex:1];

  XCTAssertEqualObjects(@"<none>", [first extensionKey]);
  XCTAssertEqual((unsigned long long)40, [first bytes]);
  XCTAssertEqualObjects(@"txt", [second extensionKey]);
  XCTAssertEqual((NSUInteger)2, [second fileCount]);
  XCTAssertEqualWithAccuracy(38.4615, [second percentageOfTotal:[root aggregateSize]], 0.01);
}

- (LDExtensionStats *)stats:(NSString *)key bytes:(unsigned long long)bytes files:(NSUInteger)files
{
  LDExtensionStats *entry = [[LDExtensionStats alloc] initWithExtensionKey:key];
  for (NSUInteger i = 0; i < files; i++) {
    [entry addBytes:i == 0 ? bytes : 0];
  }
  return entry;
}

// WinDirStat 2.8 (04b336dc): the grouped extensions are one colour unit,
// ranked by their sum; the others keep their own rank.
- (void)testGroupedExtensionsShareOneRankedColour
{
  LDExtensionStats *a = [self stats:@"a" bytes:100 files:1];
  LDExtensionStats *d = [self stats:@"d" bytes:80 files:2];
  LDExtensionStats *b = [self stats:@"b" bytes:60 files:3];
  LDExtensionStats *c = [self stats:@"c" bytes:50 files:1];
  NSArray *sorted = @[a, d, b, c];
  NSSet *grouped = [NSSet setWithObjects:@"b", @"c", nil];
  [LDExtensionStats assignColorsToSortedStats:sorted metric:LDSizeMetricLogical grouping:grouped];
  // b + c = 110 outranks a (100) and d (80).
  XCTAssertEqual((NSUInteger)0, [b colorIndex]);
  XCTAssertEqual((NSUInteger)0, [c colorIndex]);
  XCTAssertEqual((NSUInteger)1, [a colorIndex]);
  XCTAssertEqual((NSUInteger)2, [d colorIndex]);

  NSArray *rows = [LDExtensionStats rowsForStats:sorted grouping:grouped];
  XCTAssertEqual((NSUInteger)3, [rows count]);
  XCTAssertEqual(a, [rows objectAtIndex:0]);
  XCTAssertEqual(d, [rows objectAtIndex:1]);
  LDExtensionStats *group = [rows lastObject];
  XCTAssertTrue([group isGroup]);
  XCTAssertFalse([a isGroup]);
  XCTAssertEqualObjects(LDExtensionGroupKey, [group extensionKey]);
  XCTAssertEqualObjects(@"\u2026", [group displayName]);
  XCTAssertEqual((unsigned long long)110, [group bytes]);
  XCTAssertEqual((NSUInteger)4, [group fileCount]);
  XCTAssertEqual((NSUInteger)0, [group colorIndex]);
  XCTAssertEqualObjects(grouped, [group groupedKeys]);
  // The treemap colours the members, not the row.
  NSDictionary *map = [LDExtensionStats colorIndexMapForSortedStats:sorted];
  XCTAssertEqualObjects(@0, [map objectForKey:@"b"]);
  XCTAssertNil([map objectForKey:LDExtensionGroupKey]);
}

- (void)testNothingGroupedIsThePlainRanking
{
  NSArray *sorted = @[[self stats:@"a" bytes:3 files:1], [self stats:@"b" bytes:2 files:1], [self stats:@"c" bytes:1 files:1]];
  [LDExtensionStats assignColorsToSortedStats:sorted metric:LDSizeMetricLogical grouping:[NSSet set]];
  for (NSUInteger i = 0; i < [sorted count]; i++) {
    XCTAssertEqual(i, [[sorted objectAtIndex:i] colorIndex]);
  }
  XCTAssertEqual(sorted, [LDExtensionStats rowsForStats:sorted grouping:[NSSet set]]);
  XCTAssertEqualObjects(sorted, [LDExtensionStats rowsForStats:sorted grouping:[NSSet setWithObject:@"zzz"]]);
}

@end
