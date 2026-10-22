#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDExtensionColor.h"
#import "LDExtensionStats.h"
#import "LDTreemapItem.h"
#import "LDTreemapLayout.h"

@interface LDTreemapLayoutTests : XCTestCase
@end

@implementation LDTreemapLayoutTests

- (LDFileNode *)treeWithSizes:(NSArray *)sizes
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/tmp/root" kind:LDFileNodeKindDirectory size:0];
  NSUInteger i = 0;
  for (i = 0; i < [sizes count]; i++) {
    unsigned long long size = [[sizes objectAtIndex:i] unsignedLongLongValue];
    NSString *name = [NSString stringWithFormat:@"%c.bin", (char)('a' + i)];
    [root addChild:[LDFileNode nodeWithName:name kind:LDFileNodeKindFile size:size allocatedSize:size]];
  }
  [root recalculateAggregateSize];
  [root sortChildrenByMetric:LDSizeMetricPhysical];
  return root;
}

- (LDFileNode *)sampleTree
{
  return [self treeWithSizes:[NSArray arrayWithObjects:[NSNumber numberWithInt:30], [NSNumber numberWithInt:10], nil]];
}

- (LDTreemap *)treemapForRoot:(LDFileNode *)root width:(int)width height:(int)height
{
  return [[LDTreemap alloc] initWithRootNode:root
                                      metric:LDSizeMetricPhysical
                                       width:width
                                      height:height
                                     options:LDTreemapDefaultOptions()];
}

- (void)assertRect:(LDTreemapRect)rect left:(int)left top:(int)top right:(int)right bottom:(int)bottom
{
  XCTAssertEqual(left, rect.left);
  XCTAssertEqual(top, rect.top);
  XCTAssertEqual(right, rect.right);
  XCTAssertEqual(bottom, rect.bottom);
}

- (void)testLayoutCoversFilesProportionally
{
  NSArray *items = [LDTreemapLayout layoutItemsForRootNode:[self sampleTree] inRect:NSMakeRect(0, 0, 400, 100)];

  XCTAssertEqual((NSUInteger)2, [items count]);
  LDTreemapItem *first = [items objectAtIndex:0];
  LDTreemapItem *second = [items objectAtIndex:1];

  XCTAssertEqualObjects(@"a.bin", [[first node] displayName]);
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

- (void)testKDirStatRowsMatchWinDirStat
{
  // 100x100 with sizes 50/25/25: the first row takes 50 and 25 (the third
  // child would be thinner than the 0.4 minimum proportion), so row one is
  // 75px tall and the last child fills the remaining 25px row.
  LDFileNode *root = [self treeWithSizes:[NSArray arrayWithObjects:
                                          [NSNumber numberWithInt:50],
                                          [NSNumber numberWithInt:25],
                                          [NSNumber numberWithInt:25], nil]];
  LDTreemap *treemap = [self treemapForRoot:root width:100 height:100];
  XCTAssertEqual((NSUInteger)4, [treemap cellCount]);
  [self assertRect:[treemap rectOfCell:1] left:0 top:0 right:66 bottom:75];
  [self assertRect:[treemap rectOfCell:2] left:66 top:0 right:100 bottom:75];
  [self assertRect:[treemap rectOfCell:3] left:0 top:75 right:100 bottom:100];
}

- (void)testLeavesTileTheAreaWithoutGapsOrOverlaps
{
  NSMutableArray *sizes = [NSMutableArray array];
  int i = 0;
  for (i = 0; i < 40; i++) {
    [sizes addObject:[NSNumber numberWithInt:1000 + (i * 7919) % 50000]];
  }
  LDTreemapOptions options = LDTreemapDefaultOptions();
  int style = 0;
  for (style = 0; style < 2; style++) {
    options.style = (LDTreemapStyle)style;
    LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:[self treeWithSizes:sizes]
                                                      metric:LDSizeMetricPhysical
                                                       width:640
                                                      height:360
                                                     options:options];
    NSMutableData *coverage = [NSMutableData dataWithLength:640 * 360];
    uint8_t *hits = [coverage mutableBytes];
    NSUInteger c = 0;
    for (c = 0; c < [treemap cellCount]; c++) {
      if (![treemap isCellRendered:c]) {
        continue;
      }
      LDTreemapRect rect = [treemap rectOfCell:c];
      int x = 0;
      int y = 0;
      for (y = rect.top; y < rect.bottom; y++) {
        for (x = rect.left; x < rect.right; x++) {
          hits[y * 640 + x]++;
        }
      }
    }
    NSUInteger p = 0;
    for (p = 0; p < 640 * 360; p++) {
      if (hits[p] != 1) {
        XCTFail(@"style %d pixel %lu covered %u times", style, (unsigned long)p, hits[p]);
        break;
      }
    }
  }
}

- (void)testHitTestingDescendsToLeaf
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/r" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *dir = [LDFileNode nodeWithName:@"dir" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  LDFileNode *inner = [LDFileNode nodeWithName:@"inner.txt" kind:LDFileNodeKindFile size:60 allocatedSize:60];
  [dir addChild:inner];
  [root addChild:dir];
  [root addChild:[LDFileNode nodeWithName:@"outer.txt" kind:LDFileNodeKindFile size:40 allocatedSize:40]];
  [root recalculateAggregateSize];
  [root sortChildrenByMetric:LDSizeMetricPhysical];

  LDTreemap *treemap = [self treemapForRoot:root width:100 height:100];
  NSInteger index = [treemap cellIndexAtX:10 y:10];
  XCTAssertTrue(index >= 0);
  XCTAssertEqual(inner, [treemap nodeOfCell:(NSUInteger)index]);
  XCTAssertEqual(-1, [treemap cellIndexAtX:100 y:10]);
  XCTAssertEqual(inner, [treemap nodeOfCell:(NSUInteger)[treemap cellIndexForNode:inner]]);
  XCTAssertEqual(dir, [treemap nodeOfCell:(NSUInteger)[treemap cellIndexForNode:dir]]);
}

// WinDirStat 2.5.7 (86abc10a): hit testing stops at an item of size 0; here
// such items are never subdivided, so their children are never hit.
- (void)testHitTestingStopsAtZeroSizeItems
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/r" kind:LDFileNodeKindDirectory size:0];
  LDFileNode *empty = [LDFileNode nodeWithName:@"empty" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [empty addChild:[LDFileNode nodeWithName:@"blank.txt" kind:LDFileNodeKindFile size:0 allocatedSize:0]];
  [root addChild:empty];
  [root recalculateAggregateSize];

  LDTreemap *treemap = [self treemapForRoot:root width:100 height:100];
  NSInteger index = [treemap cellIndexAtX:50 y:50];
  XCTAssertTrue(index >= 0);
  XCTAssertEqual(root, [treemap nodeOfCell:(NSUInteger)index]);
}

- (void)testZeroSizeRootRendersBlack
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/empty" kind:LDFileNodeKindDirectory size:0];
  LDTreemap *treemap = [self treemapForRoot:root width:4 height:4];
  NSData *rendered = [treemap renderRGBAWithColorIndexes:nil];
  const uint8_t *pixels = [rendered bytes];
  XCTAssertEqual(0, pixels[0]);
  XCTAssertEqual(0, pixels[1]);
  XCTAssertEqual(0, pixels[2]);
  XCTAssertEqual(255, pixels[3]);
}

- (void)testFlatShadingUsesPaletteTimesBrightness
{
  LDTreemapOptions options = LDTreemapDefaultOptions();
  options.ambientLight = 1.0; // Disables cushions.
  LDFileNode *root = [self treeWithSizes:[NSArray arrayWithObject:[NSNumber numberWithInt:10]]];
  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricPhysical width:8 height:8 options:options];
  NSDictionary *colors = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:@"bin"];
  NSData *rendered = [treemap renderRGBAWithColorIndexes:colors];
  const uint8_t *pixels = [rendered bytes];

  // #6565FF * (0.88 / 0.6) overflows blue; NormalizeColor spills it into red and green.
  XCTAssertEqual(207, pixels[0]);
  XCTAssertEqual(207, pixels[1]);
  XCTAssertEqual(255, pixels[2]);
}

- (void)testCushionsAreLitFromTopLeft
{
  LDFileNode *root = [self treeWithSizes:[NSArray arrayWithObject:[NSNumber numberWithInt:10]]];
  LDTreemap *treemap = [self treemapForRoot:root width:64 height:64];
  NSDictionary *colors = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:1] forKey:@"bin"];
  NSData *rendered = [treemap renderRGBAWithColorIndexes:colors];
  const uint8_t *pixels = [rendered bytes];

  int topLeft = pixels[(4 * 64 + 4) * 4] + pixels[(4 * 64 + 4) * 4 + 1] + pixels[(4 * 64 + 4) * 4 + 2];
  int bottomRight = pixels[(59 * 64 + 59) * 4] + pixels[(59 * 64 + 59) * 4 + 1] + pixels[(59 * 64 + 59) * 4 + 2];
  XCTAssertTrue(topLeft > bottomRight + 100);
}

- (void)testRenderingIsDeterministic
{
  LDFileNode *root = [self treeWithSizes:[NSArray arrayWithObjects:
                                          [NSNumber numberWithInt:7],
                                          [NSNumber numberWithInt:5],
                                          [NSNumber numberWithInt:3], nil]];
  NSData *first = [[self treemapForRoot:root width:120 height:80] renderRGBAWithColorIndexes:nil];
  NSData *second = [[self treemapForRoot:root width:120 height:80] renderRGBAWithColorIndexes:nil];
  XCTAssertEqualObjects(first, second);
}

@end
