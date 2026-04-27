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

@end
