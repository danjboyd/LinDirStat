#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>
#import "LDLayoutDump.h"
#import "LDTreemapView.h"

@interface LDLayoutDumpTests : XCTestCase
@end

@implementation LDLayoutDumpTests

- (void)testDumpIsOffUnlessAPathIsGiven
{
  XCTAssertNil([LDLayoutDump requestedPathInEnvironment:@{}]);
  XCTAssertNil([LDLayoutDump requestedPathInEnvironment:@{@"LINDIRSTAT_DUMP_LAYOUT": @""}]);
  XCTAssertEqualObjects(@"/tmp/layout.json",
                        [LDLayoutDump requestedPathInEnvironment:@{@"LINDIRSTAT_DUMP_LAYOUT": @"/tmp/layout.json"}]);
}

- (void)testScreenRectsAreFlippedToTheTopLeftWithRoundedEdges
{
  NSArray *rect = [LDLayoutDump arrayForScreenRect:NSMakeRect(100, 31, 1280, 394.5) screenHeight:1000];
  // Top edge 1000 - 425.5 and bottom edge 1000 - 31, each rounded.
  XCTAssertEqualObjects((@[@100, @575, @1280, @394]), rect);
  NSArray *above = [LDLayoutDump arrayForScreenRect:NSMakeRect(100, 425.5, 1280, 393.5) screenHeight:1000];
  // Adjacent views stay adjacent: this one ends where the other starts.
  XCTAssertEqual([[above objectAtIndex:1] doubleValue] + [[above objectAtIndex:3] doubleValue],
                 [[rect objectAtIndex:1] doubleValue]);
}

- (void)testHitTestSamplesCollapseIntoRuns
{
  NSNull *none = [NSNull null];
  NSArray *samples = @[none, @"a", @"a", @"a", none, @"b", @"b", @"a"];
  NSArray *runs = [LDLayoutDump runsOfSamples:samples start:10 step:1];
  XCTAssertEqual((NSUInteger)3, [runs count]);
  XCTAssertEqualObjects((@{@"item": @"a", @"start": @11, @"end": @13}), [runs objectAtIndex:0]);
  XCTAssertEqualObjects((@{@"item": @"b", @"start": @15, @"end": @16}), [runs objectAtIndex:1]);
  XCTAssertEqualObjects((@{@"item": @"a", @"start": @17, @"end": @17}), [runs objectAtIndex:2]);
  NSArray *empty = [LDLayoutDump runsOfSamples:@[none, none] start:0 step:1];
  XCTAssertEqual((NSUInteger)0, [empty count]);
}

- (void)testViewTreesNameRolesAndFlagFractionalFrames
{
  NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
  NSView *whole = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 150)];
  NSView *half = [[NSView alloc] initWithFrame:NSMakeRect(0, 150.5, 400, 149.5)];
  NSView *hidden = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
  [hidden setHidden:YES];
  [root addSubview:whole];
  [root addSubview:half];
  [root addSubview:hidden];
  NSMapTable *roles = [NSMapTable strongToStrongObjectsMapTable];
  [roles setObject:@"treemap" forKey:half];

  NSDictionary *tree = [LDLayoutDump describeViewTree:root roles:roles];
  NSArray *children = [tree objectForKey:@"children"];
  XCTAssertEqual((NSUInteger)2, [children count]);
  XCTAssertNil([[children objectAtIndex:0] objectForKey:@"subpixel"]);
  XCTAssertEqualObjects(@"treemap", [[children objectAtIndex:1] objectForKey:@"role"]);
  XCTAssertEqualObjects(@YES, [[children objectAtIndex:1] objectForKey:@"subpixel"]);
}

- (void)testWritesJSON
{
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"lindirstat-layout-%d.json", getpid()]];
  NSDictionary *layout = @{@"sequence": @1, @"rect": @[@0, @0, @10, @10]};
  XCTAssertTrue([LDLayoutDump writeJSONObject:layout toPath:path]);
  NSDictionary *read = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
  XCTAssertEqualObjects(@1, [read objectForKey:@"sequence"]);
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

// The treemap is blitted 1:1, so its area keeps to whole pixels when the
// view sits on half pixels (as beside GNUstep's 1px split view dividers).
- (void)testWholePixelRectStaysInside
{
  NSRect half = NSMakeRect(0.0, 0.5, 300.0, 394.5);
  XCTAssertTrue(NSEqualRects(NSMakeRect(0, 1, 300, 394), LDWholePixelRectInside(half)));
  NSRect whole = NSMakeRect(100.0, 31.0, 1280.0, 394.0);
  XCTAssertTrue(NSEqualRects(whole, LDWholePixelRectInside(whole)));
  NSRect sliver = NSMakeRect(10.2, 10.2, 0.5, 0.5);
  XCTAssertEqual(0.0, NSWidth(LDWholePixelRectInside(sliver)));
  XCTAssertEqual(0.0, NSHeight(LDWholePixelRectInside(sliver)));
}

- (void)testTreemapAreaLeavesTheShadowEdge
{
  // WinDirStat's 1px right and bottom edge stays outside the cells.
  LDTreemapView *treemap = [[LDTreemapView alloc] initWithFrame:NSMakeRect(0, 0, 300, 394)];
  XCTAssertTrue(NSEqualRects(NSMakeRect(0, 0, 299, 393), [treemap treemapArea]));
}

@end
