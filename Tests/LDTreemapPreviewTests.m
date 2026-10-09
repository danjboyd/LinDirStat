#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDTreemapPreview.h"

@interface LDTreemapPreviewTests : XCTestCase
@end

@implementation LDTreemapPreviewTests

- (void)testDemoTreeIsWinDirStats
{
  LDFileNode *root = [[LDTreemapPreview sharedPreview] rootNode];
  // 30 + 8 + 10 + 160 + 3 leaves (TreeMap.cpp BuildDemoData).
  XCTAssertEqual((NSUInteger)211, [root fileCount]);
  unsigned long long expected = 0;
  for (NSUInteger i = 0; i < 30; i++) expected += 1 + 100 * i;
  for (NSUInteger i = 0; i < 8; i++) expected += 500 + 600 * i;
  for (NSUInteger i = 0; i < 10; i++) expected += 1 + 200 * i;
  for (NSUInteger i = 0; i < 160; i++) expected += 1 + i;
  expected += 10000 + 6000 + 1500;
  XCTAssertEqual(expected, [root aggregateAllocatedSize]);
  // Sorted by descending size for the treemap.
  NSArray *children = [root children];
  XCTAssertEqual((NSUInteger)2, [children count]);
  XCTAssertTrue([[children objectAtIndex:0] aggregateAllocatedSize] >= [[children objectAtIndex:1] aggregateAllocatedSize]);
}

- (void)testRenderingFollowsTheOptions
{
  LDTreemapPreview *preview = [LDTreemapPreview sharedPreview];
  LDTreemapOptions options = LDTreemapDefaultOptions();
  NSData *plain = [preview renderRGBAWithWidth:120 height:80 options:options];
  XCTAssertEqual((NSUInteger)(120 * 80 * 4), [plain length]);
  options.grid = YES;
  options.gridColor = LDRGB(255, 0, 0);
  NSData *grid = [preview renderRGBAWithWidth:120 height:80 options:options];
  XCTAssertFalse([plain isEqualToData:grid]);
}

@end
