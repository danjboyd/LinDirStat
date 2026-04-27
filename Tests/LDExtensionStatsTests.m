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

@end
