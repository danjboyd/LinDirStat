#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"

@interface LDFileNodeTests : XCTestCase
@end

@implementation LDFileNodeTests

- (void)testAggregatesChildSizesAndCounts
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/tmp/root" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *subdir = [LDFileNode nodeWithPath:@"/tmp/root/subdir" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *fileA = [LDFileNode nodeWithPath:@"/tmp/root/a.txt" kind:LDFileNodeKindFile size:10];
  LDFileNode *fileB = [LDFileNode nodeWithPath:@"/tmp/root/subdir/b.bin" kind:LDFileNodeKindFile size:25];

  [subdir addChild:fileB];
  [root addChild:fileA];
  [root addChild:subdir];
  [root recalculateAggregateSize];

  XCTAssertEqual((unsigned long long)35, [root aggregateSize]);
  XCTAssertEqual((NSUInteger)2, [root fileCount]);
  XCTAssertEqual((NSUInteger)2, [root directoryCount]);
  XCTAssertEqual(root, [subdir parent]);
}

- (void)testSnapshotContainsStableShape
{
  LDFileNode *node = [LDFileNode nodeWithPath:@"/tmp/example.dat" kind:LDFileNodeKindFile size:12];
  NSDictionary *snapshot = [node snapshotDictionary];

  XCTAssertEqualObjects(@"/tmp/example.dat", [snapshot objectForKey:@"path"]);
  XCTAssertEqualObjects(@"example.dat", [snapshot objectForKey:@"display_name"]);
  XCTAssertEqualObjects([NSNumber numberWithUnsignedLongLong:12], [snapshot objectForKey:@"aggregate_size"]);
}

- (void)testAggregatesPhysicalAndLogicalSizesSeparately
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/tmp/root" kind:LDFileNodeKindDirectory size:0];
  [root addChild:[LDFileNode nodeWithName:@"small.txt" kind:LDFileNodeKindFile size:10 allocatedSize:4096]];
  [root addChild:[LDFileNode nodeWithName:@"sparse.img" kind:LDFileNodeKindFile size:1000000 allocatedSize:8192]];
  [root recalculateAggregateSize];

  XCTAssertEqual((unsigned long long)1000010, [root aggregateSizeForMetric:LDSizeMetricLogical]);
  XCTAssertEqual((unsigned long long)12288, [root aggregateSizeForMetric:LDSizeMetricPhysical]);
}

- (void)testSortsChildrenByChosenMetric
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/tmp/root" kind:LDFileNodeKindDirectory size:0];
  [root addChild:[LDFileNode nodeWithName:@"small.txt" kind:LDFileNodeKindFile size:10 allocatedSize:4096]];
  [root addChild:[LDFileNode nodeWithName:@"sparse.img" kind:LDFileNodeKindFile size:1000000 allocatedSize:0]];
  [root recalculateAggregateSize];

  [root sortChildrenByMetric:LDSizeMetricPhysical];
  XCTAssertEqualObjects(@"small.txt", [[[root children] objectAtIndex:0] displayName]);

  [root sortChildrenByMetric:LDSizeMetricLogical];
  XCTAssertEqualObjects(@"sparse.img", [[[root children] objectAtIndex:0] displayName]);
}

- (void)testNamedNodesDerivePathFromParent
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *dir = [LDFileNode nodeWithName:@"photos" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  LDFileNode *file = [LDFileNode nodeWithName:@"a.jpg" kind:LDFileNodeKindFile size:1 allocatedSize:1];
  [root addChild:dir];
  [dir addChild:file];

  XCTAssertEqualObjects(@"/data/photos/a.jpg", [file path]);
  XCTAssertEqual((NSUInteger)2, [file depth]);
  XCTAssertTrue([root isAncestorOf:file]);
  XCTAssertFalse([dir isAncestorOf:root]);
}

- (void)testDirectoryLastChangeIsNewestInSubtree
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  [root setModificationTime:100];
  LDFileNode *file = [LDFileNode nodeWithName:@"a" kind:LDFileNodeKindFile size:1 allocatedSize:1];
  [file setModificationTime:500];
  [root addChild:file];
  [root recalculateAggregateSize];

  XCTAssertEqualWithAccuracy(500.0, [root aggregateModificationTime], 0.001);
  XCTAssertEqualWithAccuracy(100.0, [root modificationTime], 0.001);
}

@end
