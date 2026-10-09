#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>
#import "LDFileNode.h"
#import "LDExtensionStats.h"
#import "LDLargestFiles.h"
#import "LDScanResults.h"
#import "LDScanSession.h"
#import "LDTreemapLayout.h"
#import "LDTreemapView.h"

@interface LDScanResultsTests : XCTestCase
{
  unsigned long long _seed;
}
@end

@implementation LDScanResultsTests

- (NSString *)fixturePath
{
  return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Tests/Fixtures/basic-tree"];
}

- (unsigned long long)nextRandom
{
  _seed ^= _seed << 13;
  _seed ^= _seed >> 7;
  _seed ^= _seed << 17;
  return _seed;
}

- (NSArray *)keysOf:(NSArray *)stats
{
  NSMutableArray *keys = [NSMutableArray array];
  for (LDExtensionStats *entry in stats) {
    [keys addObject:[NSString stringWithFormat:@"%@ %llu %lu %lu", [entry extensionKey], [entry bytes],
                     (unsigned long)[entry fileCount], (unsigned long)[entry colorIndex]]];
  }
  return keys;
}

// A tree wide and deep enough that -finishTreeSortedByMetric:retiring:
// splits it into parallel subtrees. Equal sizes and extension keys that are
// equal but not identical are common on purpose.
- (LDFileNode *)randomTreeWithSeed:(unsigned long long)seed
{
  static NSString *const extensions[] = { @"c", @"h", @"txt", @"png", @"" };
  _seed = seed;
  LDFileNode *root = [LDFileNode nodeWithPath:@"/random" kind:LDFileNodeKindDirectory size:0];
  NSMutableArray *level = [NSMutableArray arrayWithObject:root];
  for (NSUInteger depth = 0; depth < 4; depth++) {
    NSMutableArray *next = [NSMutableArray array];
    for (LDFileNode *directory in level) {
      NSUInteger files = [self nextRandom] % 6;
      for (NSUInteger index = 0; index < files; index++) {
        NSString *extension = extensions[[self nextRandom] % 5];
        NSString *name = [extension length] > 0 ? [NSString stringWithFormat:@"f%lu.%@", (unsigned long)index, extension]
                                                : [NSString stringWithFormat:@"f%lu", (unsigned long)index];
        unsigned long long size = ([self nextRandom] % 4) * 100;
        LDFileNode *file = [LDFileNode nodeWithName:name kind:LDFileNodeKindFile size:size
                                      allocatedSize:([self nextRandom] % 3) * 4096];
        [file setModificationTime:(NSTimeInterval)([self nextRandom] % 100000)];
        [directory addChild:file];
      }
      NSUInteger subdirectories = depth == 0 ? 20 : [self nextRandom] % 5;
      for (NSUInteger index = 0; index < subdirectories; index++) {
        LDFileNode *child = [LDFileNode nodeWithName:[NSString stringWithFormat:@"d%lu", (unsigned long)index]
                                                kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
        [directory addChild:child];
        [next addObject:child];
      }
    }
    level = next;
  }
  return root;
}

- (void)assertTree:(LDFileNode *)left matches:(LDFileNode *)right
{
  XCTAssertEqualObjects([left displayName], [right displayName]);
  XCTAssertEqual([left aggregateSize], [right aggregateSize]);
  XCTAssertEqual([left aggregateAllocatedSize], [right aggregateAllocatedSize]);
  XCTAssertEqual([left fileCount], [right fileCount]);
  XCTAssertEqual([left directoryCount], [right directoryCount]);
  XCTAssertEqual([left aggregateModificationTime], [right aggregateModificationTime]);
  XCTAssertEqual([[left children] count], [[right children] count]);
  NSUInteger count = MIN([[left children] count], [[right children] count]);
  for (NSUInteger index = 0; index < count; index++) {
    [self assertTree:[[left children] objectAtIndex:index] matches:[[right children] objectAtIndex:index]];
  }
}

- (NSUInteger)directoriesWithChildrenIn:(LDFileNode *)node
{
  NSUInteger count = [[node children] count] > 0 ? 1 : 0;
  for (LDFileNode *child in [node children]) {
    count += [self directoriesWithChildrenIn:child];
  }
  return count;
}

- (void)testFinishingTheTreeMatchesTotallingThenSorting
{
  for (int metric = LDSizeMetricPhysical; metric <= LDSizeMetricLogical; metric++) {
    LDFileNode *expected = [self randomTreeWithSeed:42];
    [expected recalculateAggregateSize];
    [expected sortChildrenByMetric:(LDSizeMetric)metric];

    LDFileNode *finished = [self randomTreeWithSeed:42];
    NSUInteger directories = [self directoriesWithChildrenIn:finished];
    NSMutableArray *retired = [NSMutableArray array];
    [finished finishTreeSortedByMetric:(LDSizeMetric)metric retiring:retired];

    XCTAssertTrue([finished directoryCount] > 300);
    [self assertTree:finished matches:expected];
    XCTAssertEqual(directories, [retired count]);
  }
}

- (void)testFinishingAFileOrAnEmptyFolderIsHarmless
{
  LDFileNode *file = [LDFileNode nodeWithPath:@"/file" kind:LDFileNodeKindFile size:5];
  [file finishTreeSortedByMetric:LDSizeMetricLogical retiring:nil];
  LDFileNode *folder = [LDFileNode nodeWithPath:@"/empty" kind:LDFileNodeKindDirectory size:0];
  [folder finishTreeSortedByMetric:LDSizeMetricLogical retiring:nil];

  XCTAssertEqual((unsigned long long)5, [file aggregateSize]);
  XCTAssertEqual((NSUInteger)1, [folder directoryCount]);
  XCTAssertEqual((NSUInteger)0, [[folder children] count]);
}

- (void)testOneWalkGivesStatisticsAndLargestFiles
{
  LDFileNode *root = [self randomTreeWithSeed:7];
  [root finishTreeSortedByMetric:LDSizeMetricLogical retiring:nil];

  NSArray *largest = nil;
  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root metric:LDSizeMetricLogical largestFiles:&largest count:25];

  XCTAssertEqualObjects([LDLargestFiles largestFilesUnderNode:root count:25], largest);
  // Keys made separately for each file are still counted once per extension.
  NSMutableSet *keys = [NSMutableSet set];
  NSUInteger files = 0;
  unsigned long long bytes = 0;
  for (LDExtensionStats *entry in stats) {
    XCTAssertFalse([keys containsObject:[entry extensionKey]]);
    [keys addObject:[entry extensionKey]];
    files += [entry fileCount];
    bytes += [entry bytes];
  }
  XCTAssertEqual((NSUInteger)5, [stats count]);
  XCTAssertEqual([root fileCount], files);
  XCTAssertEqual([root aggregateSize], bytes);
  XCTAssertEqualObjects([self keysOf:stats],
                        [self keysOf:[LDExtensionStats sortedStatsForRootNode:root metric:LDSizeMetricLogical]]);
}

- (LDScanSession *)scanFixtureWithRequest:(LDScanResultsRequest *)request
{
  LDScanSession *session = [[LDScanSession alloc] init];
  [session setSortMetric:[request metric]];
  [session setResultsRequest:request];
  __block BOOL called = NO;
  [session startAsyncScanPath:[self fixturePath] completion:^{
    called = YES;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (!called && [[NSDate date] compare:deadline] == NSOrderedAscending) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  XCTAssertTrue(called);
  return session;
}

- (void)testScanWorksOutWhatTheViewsNeed
{
  LDScanResultsRequest *request = [LDScanResultsRequest requestWithMetric:LDSizeMetricLogical largestFileCount:3];
  [request setTreemapWidth:120 height:80 options:LDTreemapDefaultOptions()];
  LDScanSession *session = [self scanFixtureWithRequest:request];
  LDScanResults *results = [session results];
  LDFileNode *root = [session rootNode];

  XCTAssertNotNil(results);
  XCTAssertTrue([results rootNode] == root);
  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root metric:LDSizeMetricLogical];
  XCTAssertEqualObjects([self keysOf:stats], [self keysOf:[results extensionStats]]);
  XCTAssertEqualObjects([LDExtensionStats colorIndexMapForSortedStats:stats], [results colorIndexes]);
  XCTAssertEqualObjects([LDLargestFiles largestFilesUnderNode:root count:3], [results largestFiles]);
  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricLogical width:120 height:80
                                                   options:LDTreemapDefaultOptions()];
  XCTAssertEqual([treemap cellCount], [[results treemap] cellCount]);
  XCTAssertEqualObjects([treemap renderRGBAWithColorIndexes:[results colorIndexes]], [results treemapPixels]);
}

- (void)testNoRequestNoResultsAndNoTreemapWhenNotAsked
{
  LDScanSession *session = [self scanFixtureWithRequest:nil];
  XCTAssertNil([session results]);

  LDScanResultsRequest *request = [LDScanResultsRequest requestWithMetric:LDSizeMetricPhysical largestFileCount:0];
  session = [self scanFixtureWithRequest:request];
  XCTAssertNotNil([session results]);
  XCTAssertNil([[session results] treemap]);
  XCTAssertEqualObjects(@[], [[session results] largestFiles]);
}

- (void)testTreemapViewAdoptsAMatchingTreemapOnly
{
  LDScanSession *session = [self scanFixtureWithRequest:[LDScanResultsRequest requestWithMetric:LDSizeMetricLogical
                                                                                largestFileCount:0]];
  LDFileNode *root = [session rootNode];
  LDTreemapView *view = [[LDTreemapView alloc] initWithFrame:NSMakeRect(0, 0, 121, 81)];
  XCTAssertTrue(NSEqualSizes(NSMakeSize(120, 80), [view renderSize]));

  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricLogical width:120 height:80
                                                   options:[view options]];
  NSData *pixels = [treemap renderRGBAWithColorIndexes:nil];
  [view setRootNode:root metric:LDSizeMetricLogical colorIndexes:nil treemap:treemap pixels:pixels];
  XCTAssertTrue([view treemap] == treemap);

  [view setRootNode:root metric:LDSizeMetricPhysical colorIndexes:nil treemap:treemap pixels:pixels];
  XCTAssertNil([view treemap]);

  LDTreemap *small = [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricLogical width:60 height:80
                                                 options:[view options]];
  [view setRootNode:root metric:LDSizeMetricLogical colorIndexes:nil treemap:small
             pixels:[small renderRGBAWithColorIndexes:nil]];
  XCTAssertNil([view treemap]);
}

@end
