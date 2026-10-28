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

// #57: a 0 B (or unreadable) root is empty and renders transparent, not
// black; the view shows the window colour, as CTreeMap::DrawTreemap does.
- (void)testZeroSizeRootRendersTransparent
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/empty" kind:LDFileNodeKindDirectory size:0];
  LDTreemap *treemap = [self treemapForRoot:root width:4 height:4];
  XCTAssertTrue([treemap isEmpty]);
  NSData *rendered = [treemap renderRGBAWithColorIndexes:nil];
  XCTAssertEqual((NSUInteger)(4 * 4 * 4), [rendered length]);
  const uint8_t *pixels = [rendered bytes];
  for (NSUInteger i = 0; i < [rendered length]; i++) {
    XCTAssertEqual(0, pixels[i]);
  }
  // The root is still a cell, so it can be hit and selected.
  XCTAssertEqual((NSUInteger)1, [treemap cellCount]);
  XCTAssertEqual(root, [treemap nodeOfCell:(NSUInteger)[treemap cellIndexAtX:2 y:2]]);
}

- (void)testSizedRootIsNotEmpty
{
  LDFileNode *root = [self treeWithSizes:[NSArray arrayWithObject:[NSNumber numberWithInt:10]]];
  XCTAssertFalse([[self treemapForRoot:root width:4 height:4] isEmpty]);
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

#pragma mark - Folder frames (WinDirStat 2.6-2.8: f9ada432, 549d7f20)

// /r holds two folders, "big" (a 60 file and a 20 file) and "small" (one
// 20 file).
- (LDFileNode *)foldersTree
{
  LDFileNode *root = [LDFileNode nodeWithPath:@"/r" kind:LDFileNodeKindDirectory size:0];
  LDDirectoryNode *big = [LDFileNode nodeWithName:@"big" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [big addChild:[LDFileNode nodeWithName:@"a.bin" kind:LDFileNodeKindFile size:60 allocatedSize:60]];
  [big addChild:[LDFileNode nodeWithName:@"b.txt" kind:LDFileNodeKindFile size:20 allocatedSize:20]];
  LDDirectoryNode *small = [LDFileNode nodeWithName:@"small" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [small addChild:[LDFileNode nodeWithName:@"c.bin" kind:LDFileNodeKindFile size:20 allocatedSize:20]];
  [root addChild:big];
  [root addChild:small];
  [root recalculateAggregateSize];
  [root sortChildrenByMetric:LDSizeMetricPhysical];
  return root;
}

- (LDTreemap *)framedTreemapForRoot:(LDFileNode *)root width:(int)width height:(int)height
                          threshold:(int)threshold nameWidth:(double)nameWidth
{
  LDTreemapOptions options = LDTreemapDefaultOptions();
  options.showFolderFrames = YES;
  options.folderFramesDrawThreshold = threshold;
  options.ambientLight = 1.0; // Flat colours, so pixels are easy to check.
  LDTreemapFolderStyle style = {10, LDRGB(255, 255, 255), LDRGB(0, 0, 0)};
  return [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricPhysical width:width height:height options:options
                                 folderStyle:style
                                   textWidth:^double(NSString *text) { return nameWidth; }];
}

- (NSArray *)framedNodesOf:(LDTreemap *)treemap
{
  NSMutableArray *nodes = [NSMutableArray array];
  [treemap enumerateFolderFramesUsingBlock:^(LDFileNode *node, LDTreemapRect frame, LDTreemapRect header) {
    [nodes addObject:node];
  }];
  return nodes;
}

- (void)testFolderFramesAreOffByDefault
{
  LDTreemapOptions options = LDTreemapDefaultOptions();
  XCTAssertFalse(options.showFolderFrames);
  XCTAssertEqual(5, options.folderFramesDrawThreshold);
  XCTAssertEqual((NSUInteger)0, [[self framedNodesOf:[self treemapForRoot:[self foldersTree] width:100 height:50]] count]);
}

// Each folder below the root gets a 1-pixel frame and a header of the
// header height; its children are laid out inside, below the header.
- (void)testFramedFoldersHoldTheirChildrenBelowAHeader
{
  LDFileNode *root = [self foldersTree];
  LDTreemap *treemap = [self framedTreemapForRoot:root width:100 height:50 threshold:5 nameWidth:5];
  NSArray *framed = [self framedNodesOf:treemap];
  XCTAssertEqual((NSUInteger)2, [framed count]);
  XCTAssertFalse([framed containsObject:root]);

  __block LDTreemapRect bigFrame = {0, 0, 0, 0};
  __block LDTreemapRect bigHeader = {0, 0, 0, 0};
  [treemap enumerateFolderFramesUsingBlock:^(LDFileNode *node, LDTreemapRect frame, LDTreemapRect header) {
    if ([[node displayName] isEqualToString:@"big"]) {
      bigFrame = frame;
      bigHeader = header;
    }
  }];
  [self assertRect:bigHeader left:bigFrame.left + 1 top:bigFrame.top + 1 right:bigFrame.right - 1 bottom:bigFrame.top + 11];
  LDFileNode *big = [[root children] objectAtIndex:0];
  NSInteger bigCell = [treemap cellIndexForNode:big];
  const LDTreemapCell *cell = &[treemap cells][bigCell];
  XCTAssertEqual((uint32_t)2, cell->childCount);
  int minLeft = INT_MAX, minTop = INT_MAX, maxRight = 0, maxBottom = 0;
  uint32_t i = 0;
  for (i = 0; i < cell->childCount; i++) {
    LDTreemapRect child = [treemap rectOfCell:(NSUInteger)cell->firstChild + i];
    minLeft = MIN(minLeft, child.left);
    minTop = MIN(minTop, child.top);
    maxRight = MAX(maxRight, child.right);
    maxBottom = MAX(maxBottom, child.bottom);
  }
  XCTAssertEqual(bigFrame.left + 1, minLeft);
  XCTAssertEqual(bigHeader.bottom, minTop);
  XCTAssertEqual(bigFrame.right - 1, maxRight);
  XCTAssertEqual(bigFrame.bottom - 1, maxBottom);

  // A click on the header selects the folder.
  XCTAssertEqual(bigCell, [treemap cellIndexAtX:bigHeader.left + 2 y:bigHeader.top + 2]);
}

// The header shows only when the name fits (CTreeMap: textWidth is the
// frame's inside less 6) and the folder is taller than the header.
- (void)testHeaderNeedsRoomForTheName
{
  LDFileNode *root = [self foldersTree];
  LDTreemap *treemap = [self framedTreemapForRoot:root width:100 height:50 threshold:5 nameWidth:1000];
  __block NSUInteger headers = 0;
  __block NSUInteger frames = 0;
  [treemap enumerateFolderFramesUsingBlock:^(LDFileNode *node, LDTreemapRect frame, LDTreemapRect header) {
    frames++;
    if (LDTreemapRectWidth(header) > 0) {
      headers++;
    }
  }];
  XCTAssertEqual((NSUInteger)2, frames);
  XCTAssertEqual((NSUInteger)0, headers);

  // Without a measurer (the plain initializer) frames have no headers.
  LDTreemapOptions options = LDTreemapDefaultOptions();
  options.showFolderFrames = YES;
  LDTreemap *plain = [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricPhysical width:100 height:50 options:options];
  [plain enumerateFolderFramesUsingBlock:^(LDFileNode *node, LDTreemapRect frame, LDTreemapRect header) {
    XCTAssertEqual(0, LDTreemapRectWidth(header));
  }];
  XCTAssertEqual((NSUInteger)2, [[self framedNodesOf:plain] count]);
}

// TreeMapFolderFramesDrawThreshold: a folder whose shorter side is below it
// is not framed.
- (void)testFoldersBelowTheThresholdAreNotFramed
{
  LDFileNode *root = [self foldersTree];
  LDTreemap *treemap = [self framedTreemapForRoot:root width:100 height:50 threshold:5 nameWidth:5];
  __block int shortest = INT_MAX;
  [treemap enumerateFolderFramesUsingBlock:^(LDFileNode *node, LDTreemapRect frame, LDTreemapRect header) {
    shortest = MIN(shortest, MIN(LDTreemapRectWidth(frame), LDTreemapRectHeight(frame)));
  }];
  LDTreemap *strict = [self framedTreemapForRoot:root width:100 height:50 threshold:shortest + 1 nameWidth:5];
  XCTAssertEqual((NSUInteger)1, [[self framedNodesOf:strict] count]);
}

// CFolderColors: the root is the window colour tinted 12% towards the
// text; top-level folders take distinct palette entries blended 22% into
// the window colour, 6% more per level below.
- (void)testFolderColorsFollowBranchesAndDepth
{
  LDFileNode *root = [self foldersTree];
  LDDirectoryNode *big = (LDDirectoryNode *)[[root children] objectAtIndex:0];
  LDDirectoryNode *inner = [LDFileNode nodeWithName:@"inner" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  [inner addChild:[LDFileNode nodeWithName:@"d.bin" kind:LDFileNodeKindFile size:5 allocatedSize:5]];
  [big addChild:inner];
  [root recalculateAggregateSize];
  [root sortChildrenByMetric:LDSizeMetricPhysical];
  LDTreemap *treemap = [self framedTreemapForRoot:root width:200 height:100 threshold:5 nameWidth:5];

  XCTAssertEqual(LDRGB(224, 224, 224), [treemap folderColorForNode:root]);
  LDFileNode *small = [[root children] objectAtIndex:1];
  LDRGBColor bigColor = [treemap folderColorForNode:big];
  LDRGBColor smallColor = [treemap folderColorForNode:small];
  XCTAssertNotEqual(bigColor, smallColor);

  NSArray *palette = @[@(LDRGB(79, 157, 232)), @(LDRGB(71, 173, 128)), @(LDRGB(230, 159, 0)), @(LDRGB(213, 94, 0)),
                       @(LDRGB(168, 135, 224)), @(LDRGB(86, 180, 233)), @(LDRGB(204, 121, 167)), @(LDRGB(230, 205, 70))];
  NSUInteger bigIndex = NSNotFound;
  NSUInteger i = 0;
  for (i = 0; i < [palette count]; i++) {
    LDRGBColor entry = [[palette objectAtIndex:i] unsignedIntValue];
    LDRGBColor blended = LDRGB((int)(LDRGBRed(entry) * 0.78 + 255 * 0.22), (int)(LDRGBGreen(entry) * 0.78 + 255 * 0.22),
                               (int)(LDRGBBlue(entry) * 0.78 + 255 * 0.22));
    if (blended == bigColor) {
      bigIndex = i;
    }
  }
  XCTAssertNotEqual(NSNotFound, bigIndex, @"%06x is a 22%% blend of a palette entry", bigColor);
  if (bigIndex != NSNotFound) {
    LDRGBColor entry = [[palette objectAtIndex:bigIndex] unsignedIntValue];
    LDRGBColor deeper = LDRGB((int)(LDRGBRed(entry) * 0.72 + 255 * 0.28), (int)(LDRGBGreen(entry) * 0.72 + 255 * 0.28),
                              (int)(LDRGBBlue(entry) * 0.72 + 255 * 0.28));
    XCTAssertEqual(deeper, [treemap folderColorForNode:inner]);
  }
}

// The frame is the branch colour dimmed by 10%, the header the branch
// colour, drawn over the cells.
- (void)testFramesAndHeadersAreRendered
{
  LDFileNode *root = [self foldersTree];
  LDTreemap *treemap = [self framedTreemapForRoot:root width:100 height:50 threshold:5 nameWidth:5];
  NSData *data = [treemap renderRGBAWithColorIndexes:nil];
  const uint8_t *pixels = [data bytes];
  LDFileNode *big = [[root children] objectAtIndex:0];
  LDRGBColor color = [treemap folderColorForNode:big];
  LDTreemapRect frame = [treemap rectOfCell:(NSUInteger)[treemap cellIndexForNode:big]];
  const uint8_t *corner = pixels + ((size_t)frame.top * 100 + frame.left) * 4;
  XCTAssertEqual((int)(LDRGBRed(color) * 0.9f), corner[0]);
  XCTAssertEqual((int)(LDRGBGreen(color) * 0.9f), corner[1]);
  XCTAssertEqual((int)(LDRGBBlue(color) * 0.9f), corner[2]);
  const uint8_t *header = pixels + ((size_t)(frame.top + 5) * 100 + frame.left + 5) * 4;
  XCTAssertEqual((int)LDRGBRed(color), header[0]);
  XCTAssertEqual((int)LDRGBGreen(color), header[1]);
  XCTAssertEqual((int)LDRGBBlue(color), header[2]);
}

@end

