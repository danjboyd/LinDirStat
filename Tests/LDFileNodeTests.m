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

- (LDFileNode *)editableTree
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *dir = [LDFileNode nodeWithName:@"photos" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [dir addChild:[LDFileNode nodeWithName:@"big.jpg" kind:LDFileNodeKindFile size:900 allocatedSize:900]];
  [dir addChild:[LDFileNode nodeWithName:@"small.jpg" kind:LDFileNodeKindFile size:100 allocatedSize:100]];
  [root addChild:dir];
  [root addChild:[LDFileNode nodeWithName:@"notes.txt" kind:LDFileNodeKindFile size:500 allocatedSize:500]];
  [root recalculateAggregateSize];
  [root sortChildrenByMetric:LDSizeMetricPhysical];
  return root;
}

- (void)testPathDataIsBuiltFromNameBytes
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *dir = [LDFileNode nodeWithNameBytes:"caf\xe9" length:4 arena:nil kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  LDFileNode *file = [LDFileNode nodeWithName:@"a.txt" kind:LDFileNodeKindFile size:1 allocatedSize:1];
  [root addChild:dir];
  [dir addChild:file];

  XCTAssertEqualObjects([NSData dataWithBytes:"/caf\xe9/a.txt" length:11], [file pathData]);
  XCTAssertEqualObjects([NSData dataWithBytes:"/" length:1], [root pathData]);
}

- (void)testRemovingChildUpdatesTotalsAndOrderUpward
{
  LDFileNode *root = [self editableTree];
  LDFileNode *photos = [[root children] objectAtIndex:0];
  LDFileNode *big = [[photos children] objectAtIndex:0];
  XCTAssertEqualObjects(@"big.jpg", [big displayName]);

  [(LDDirectoryNode *)photos removeChild:big];
  [photos updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];

  XCTAssertNil([big parent]);
  XCTAssertEqual((unsigned long long)100, [photos aggregateAllocatedSize]);
  XCTAssertEqual((unsigned long long)600, [root aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)2, [root fileCount]);
  // notes.txt (500) is now larger than photos (100).
  XCTAssertEqualObjects(@"notes.txt", [[[root children] objectAtIndex:0] displayName]);
}

- (void)testReplacingChildGraftsNewSubtree
{
  LDFileNode *root = [self editableTree];
  LDFileNode *photos = [[root children] objectAtIndex:0];
  LDFileNode *fresh = [LDFileNode nodeWithName:@"photos" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [fresh addChild:[LDFileNode nodeWithName:@"new.jpg" kind:LDFileNodeKindFile size:50 allocatedSize:50]];
  [fresh recalculateAggregateSize];

  [(LDDirectoryNode *)root replaceChild:photos withNode:fresh];
  [root updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];

  XCTAssertEqual(root, [fresh parent]);
  XCTAssertEqualObjects(@"/data/photos/new.jpg", [[[fresh children] objectAtIndex:0] path]);
  XCTAssertEqual((unsigned long long)550, [root aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)2, [root fileCount]);
}

- (void)testPendingScansPropagateToParent
{
  LDDirectoryNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  LDDirectoryNode *child = [LDFileNode nodeWithName:@"sub" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [root publishChildren:@[child]];
  [root beginPendingScans:1];      // the root's own read
  [child beginPendingScans:1];     // the child's own read
  [root beginPendingScans:1];      // the root waits for the child
  [root finishPendingScan];        // the root's read is done

  XCTAssertTrue([root isScanPending]);
  XCTAssertTrue([child isScanPending]);
  [child finishPendingScan];
  XCTAssertFalse([child isScanPending]);
  XCTAssertFalse([root isScanPending]);
}

- (void)testLiveFilesAccumulateUpward
{
  LDDirectoryNode *root = [LDFileNode nodeWithPath:@"/data" kind:LDFileNodeKindDirectory size:0];
  LDDirectoryNode *child = [LDFileNode nodeWithName:@"sub" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [root publishChildren:@[child]];
  [child addLiveFiles:3 directories:0 size:300 allocatedSize:4096 modificationTime:50];

  XCTAssertEqual((unsigned long long)300, [root aggregateSize]);
  XCTAssertEqual((unsigned long long)4096, [root aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)3, [root fileCount]);
  XCTAssertEqual(50.0, [root aggregateModificationTime]);
}

@end
