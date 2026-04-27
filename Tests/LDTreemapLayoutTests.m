#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDExtensionColor.h"
#import "LDTreemapItem.h"
#import "LDTreemapLayout.h"

@interface LDTreemapLayoutTests : XCTestCase
@end

@implementation LDTreemapLayoutTests

- (LDFileNode *)sampleTree
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/tmp/root" kind:LDFileNodeKindDirectory size:0];
  [root addChild:[LDFileNode nodeWithPath:@"/tmp/root/a.txt" kind:LDFileNodeKindFile size:30]];
  [root addChild:[LDFileNode nodeWithPath:@"/tmp/root/b.bin" kind:LDFileNodeKindFile size:10]];
  [root recalculateAggregateSize];
  return root;
}

- (void)testLayoutCoversFilesProportionally
{
  NSArray *items = [LDTreemapLayout layoutItemsForRootNode:[self sampleTree] inRect:NSMakeRect(0, 0, 400, 100)];

  XCTAssertEqual((NSUInteger)2, [items count]);
  LDTreemapItem *first = [items objectAtIndex:0];
  LDTreemapItem *second = [items objectAtIndex:1];

  XCTAssertEqualObjects(@"a.txt", [[first node] displayName]);
  XCTAssertEqualWithAccuracy(300.0, [first rect].size.width, 0.01);
  XCTAssertEqualObjects(@"b.bin", [[second node] displayName]);
  XCTAssertEqualWithAccuracy(100.0, [second rect].size.width, 0.01);
}

- (void)testPointLookupReturnsDeepestItem
{
  NSArray *items = [LDTreemapLayout layoutItemsForRootNode:[self sampleTree] inRect:NSMakeRect(0, 0, 400, 100)];
  LDTreemapItem *item = [LDTreemapLayout itemAtPoint:NSMakePoint(350, 50) inItems:items];

  XCTAssertEqualObjects(@"b.bin", [[item node] displayName]);
}

- (void)testExtensionColorIsStable
{
  XCTAssertEqual([LDExtensionColor paletteIndexForExtensionKey:@"txt"],
                 [LDExtensionColor paletteIndexForExtensionKey:@"txt"]);
}

@end
