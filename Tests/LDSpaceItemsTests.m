#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDCSV.h"
#import "LDCommandRules.h"
#import "LDExtensionColor.h"
#import "LDExtensionStats.h"
#import "LDFileNode.h"
#import "LDLargestFiles.h"
#import "LDPreferences.h"
#import "LDSearch.h"
#import "LDSpaceItems.h"
#import "LDTreemapLayout.h"
#import "LDVolumes.h"

#include <unistd.h>

static const unsigned long long LDTestTotal = 1000;
static const unsigned long long LDTestFree = 300;

@interface LDSpaceItemsTests : XCTestCase
{
  LDFileNode *_volume;
  LDFileNode *_folder;
  LDFileNode *_file;
}
@end

@implementation LDSpaceItemsTests

// /vol: dir/a.txt (200 bytes) and b.txt (100 bytes) on a 1000-byte volume
// with 300 bytes free, so 400 used bytes are not in the tree.
- (void)setUp
{
  [super setUp];
  _volume = [LDFileNode nodeWithPath:@"/vol" kind:LDFileNodeKindDirectory size:0];
  _folder = [LDFileNode nodeWithName:@"dir" kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  _file = [LDFileNode nodeWithName:@"a.txt" kind:LDFileNodeKindFile size:150 allocatedSize:200];
  [_folder addChild:_file];
  [_volume addChild:_folder];
  [_volume addChild:[LDFileNode nodeWithName:@"b.txt" kind:LDFileNodeKindFile size:90 allocatedSize:100]];
  [_volume recalculateAggregateSize];
  [_volume sortChildrenByMetric:LDSizeMetricPhysical];
}

- (LDVolumeUsageQuery)usage
{
  return ^BOOL(LDFileNode *volume, unsigned long long *totalBytes, unsigned long long *freeBytes) {
    (void)volume;
    *totalBytes = LDTestTotal;
    *freeBytes = LDTestFree;
    return YES;
  };
}

- (LDVolumeUsageQuery)failingUsage
{
  return ^BOOL(LDFileNode *volume, unsigned long long *totalBytes, unsigned long long *freeBytes) {
    (void)volume;
    (void)totalBytes;
    (void)freeBytes;
    return NO;
  };
}

- (NSArray *)update:(LDFileNode *)volume free:(BOOL)showFree unknown:(BOOL)showUnknown
{
  return [LDSpaceItems updateVolumes:@[volume] showFreeSpace:showFree showUnknown:showUnknown
                               usage:[self usage] metric:LDSizeMetricPhysical];
}

- (LDFileNode *)freeItem { return [LDSpaceItems spaceItemOfKind:LDFileNodeKindFreeSpace inVolume:_volume]; }
- (LDFileNode *)unknownItem { return [LDSpaceItems spaceItemOfKind:LDFileNodeKindUnknown inVolume:_volume]; }

#pragma mark - Model

- (void)testItemsAreNamedPseudoFilesWithPhysicalSizeOnly
{
  [self update:_volume free:YES unknown:YES];
  LDFileNode *freeItem = [self freeItem];
  LDFileNode *unknown = [self unknownItem];
  XCTAssertEqualObjects(@"<Free Space>", [freeItem displayName]);
  XCTAssertEqualObjects(@"<Unknown>", [unknown displayName]);
  XCTAssertTrue([freeItem isSpaceItem]);
  XCTAssertTrue([unknown isSpaceItem]);
  XCTAssertFalse([_file isSpaceItem]);
  XCTAssertEqual(LDTestFree, [freeItem aggregateAllocatedSize]);
  XCTAssertEqual(0ULL, [freeItem aggregateSize]);
  XCTAssertEqual((NSUInteger)0, [freeItem fileCount]);
  XCTAssertEqual((NSUInteger)0, [unknown fileCount]);
  XCTAssertTrue([freeItem isLeaf]);
}

- (void)testUnknownIsUsedSpaceTheTreeDoesNotAccountFor
{
  [self update:_volume free:YES unknown:YES];
  // used 700 - tallied 300; the free item is not tallied.
  XCTAssertEqual(400ULL, [[self unknownItem] aggregateAllocatedSize]);
  [self update:_volume free:NO unknown:YES];
  XCTAssertEqual(400ULL, [[self unknownItem] aggregateAllocatedSize]);
}

- (void)testUnknownIsNeverNegative
{
  [_file setAllocatedSize:5000];
  [_folder updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
  [self update:_volume free:NO unknown:YES];
  XCTAssertEqual(0ULL, [[self unknownItem] aggregateAllocatedSize]);
}

- (void)testTotalsIncludeItemsAndChildrenAreSorted
{
  [self update:_volume free:YES unknown:YES];
  XCTAssertEqual(LDTestTotal, [_volume aggregateAllocatedSize]);
  XCTAssertEqual(240ULL, [_volume aggregateSize]);
  XCTAssertEqual((NSUInteger)2, [_volume fileCount]);
  XCTAssertEqual((NSUInteger)2, [_volume directoryCount]);
  NSArray *children = [_volume children];
  XCTAssertEqual([self unknownItem], [children objectAtIndex:0]);
  XCTAssertEqual([self freeItem], [children objectAtIndex:1]);
}

- (void)testTotalsReachTheComputerRoot
{
  LDComputerNode *computer = [LDComputerNode computerNode];
  [computer addChild:_volume];
  [computer recalculateAggregateSize];
  [LDSpaceItems updateVolumes:[LDSpaceItems volumeNodesOfRoot:computer] showFreeSpace:YES showUnknown:NO
                        usage:[self usage] metric:LDSizeMetricPhysical];
  XCTAssertEqual(600ULL, [computer aggregateAllocatedSize]);
}

- (void)testTogglingOffRemovesAndRestoresTotals
{
  [self update:_volume free:YES unknown:YES];
  LDFileNode *freeItem = [self freeItem];
  NSArray *removed = [self update:_volume free:NO unknown:YES];
  XCTAssertEqualObjects(@[freeItem], removed);
  XCTAssertNil([self freeItem]);
  XCTAssertNil([freeItem parent]);
  XCTAssertEqual(700ULL, [_volume aggregateAllocatedSize]);
  [self update:_volume free:NO unknown:NO];
  XCTAssertNil([self unknownItem]);
  XCTAssertEqual(300ULL, [_volume aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)2, [[_volume children] count]);
}

- (void)testUpdatingKeepsItemsAndRecomputesSizes
{
  [self update:_volume free:YES unknown:YES];
  LDFileNode *freeItem = [self freeItem];
  LDFileNode *unknown = [self unknownItem];
  // A refresh found more data: unknown shrinks.
  [_file setAllocatedSize:350];
  [_folder updateTotalsUpwardSortedByMetric:LDSizeMetricPhysical];
  [self update:_volume free:YES unknown:YES];
  XCTAssertEqual(freeItem, [self freeItem]);
  XCTAssertEqual(unknown, [self unknownItem]);
  XCTAssertEqual(250ULL, [unknown aggregateAllocatedSize]);
  XCTAssertEqual(LDTestTotal, [_volume aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)4, [[_volume children] count]);
}

- (void)testUnreadableVolumeKeepsLoadedItemsButCreatesNone
{
  [self update:_volume free:YES unknown:NO];
  [LDSpaceItems updateVolumes:@[_volume] showFreeSpace:YES showUnknown:YES
                        usage:[self failingUsage] metric:LDSizeMetricPhysical];
  XCTAssertEqual(LDTestFree, [[self freeItem] aggregateAllocatedSize]);
  XCTAssertNil([self unknownItem]);
  [LDSpaceItems updateVolumes:@[_volume] showFreeSpace:NO showUnknown:NO
                        usage:[self failingUsage] metric:LDSizeMetricPhysical];
  XCTAssertNil([self freeItem]);
}

- (void)testVolumeNodes
{
  BOOL (^never)(LDFileNode *) = ^BOOL(LDFileNode *node) { (void)node; return NO; };
  BOOL (^always)(LDFileNode *) = ^BOOL(LDFileNode *node) { (void)node; return YES; };
  XCTAssertEqualObjects(@[], [LDSpaceItems volumeNodesOfRoot:_volume isVolumeRoot:never]);
  XCTAssertEqualObjects(@[_volume], [LDSpaceItems volumeNodesOfRoot:_volume isVolumeRoot:always]);
  XCTAssertEqualObjects(@[], [LDSpaceItems volumeNodesOfRoot:_file isVolumeRoot:always]);
  XCTAssertEqualObjects(@[], [LDSpaceItems volumeNodesOfRoot:nil isVolumeRoot:always]);

  // A loaded tree that already holds the items is a volume.
  [self update:_volume free:YES unknown:NO];
  XCTAssertEqualObjects(@[_volume], [LDSpaceItems volumeNodesOfRoot:_volume isVolumeRoot:never]);

  LDComputerNode *computer = [LDComputerNode computerNode];
  LDFileNode *other = [LDFileNode nodeWithPath:@"/other" kind:LDFileNodeKindDirectory size:0];
  [computer addChild:_volume];
  [computer addChild:other];
  NSArray *volumes = [LDSpaceItems volumeNodesOfRoot:computer isVolumeRoot:never];
  XCTAssertEqual((NSUInteger)2, [volumes count]);
  XCTAssertTrue([volumes containsObject:other]);
}

#pragma mark - Disk helpers

- (void)testFilesystemRootIsAVolumeRootAndATemporaryFolderIsNot
{
  XCTAssertTrue([LDVolumes isVolumeRootPathData:[NSData dataWithBytes:"/" length:1]]);
  NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"lindirstat-space-%d", getpid()]];
  [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
  NSData *path = [NSData dataWithBytes:[folder fileSystemRepresentation] length:strlen([folder fileSystemRepresentation])];
  XCTAssertFalse([LDVolumes isVolumeRootPathData:path]);
  unsigned long long total = 0;
  unsigned long long freeBytes = 0;
  XCTAssertTrue([LDVolumes getTotalBytes:&total freeBytes:&freeBytes forPathData:path]);
  XCTAssertTrue(total > 0);
  XCTAssertTrue(freeBytes <= total);
  [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
  XCTAssertFalse([LDVolumes isVolumeRootPathData:path]);
  XCTAssertFalse([LDVolumes getTotalBytes:&total freeBytes:&freeBytes forPathData:path]);
  XCTAssertFalse([LDVolumes isVolumeRootPathData:[NSData data]]);
}

#pragma mark - Exclusions

- (void)testItemsAreNotFilesForStatsListsAndSearch
{
  [self update:_volume free:YES unknown:YES];
  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:_volume metric:LDSizeMetricPhysical];
  XCTAssertEqual((NSUInteger)1, [stats count]);
  XCTAssertEqualObjects(@"txt", [[stats objectAtIndex:0] extensionKey]);

  XCTAssertFalse([LDLargestFiles isRankableFile:[self freeItem]]);
  XCTAssertFalse([LDLargestFiles isRankableFile:[self unknownItem]]);
  NSArray *largest = [LDLargestFiles largestFilesUnderNode:_volume count:10];
  XCTAssertEqual((NSUInteger)2, [largest count]);

  LDSearchResult *result = [LDSearch searchNode:_volume options:[LDSearchOptions optionsWithTerm:@"*"] maxResults:0];
  for (LDFileNode *node in [result nodes]) {
    XCTAssertFalse([node isSpaceItem]);
  }
  XCTAssertEqual((NSUInteger)0, [[[LDSearch searchNode:_volume options:[LDSearchOptions optionsWithTerm:@"Free"] maxResults:0] nodes] count]);
}

- (void)testNoCommandAppliesToItems
{
  [self update:_volume free:YES unknown:YES];
  LDFileNode *freeItem = [self freeItem];
  NSArray *mixed = [NSArray arrayWithObjects:_file, [self unknownItem], nil];
  int command = 0;
  for (command = LDCommandOpen; command <= LDCommandCustomCleanup; command++) {
    XCTAssertFalse([LDCommandRules isCommand:(LDCommand)command enabledForNodes:@[freeItem] rootNode:_volume busy:NO]);
    XCTAssertFalse([LDCommandRules isCommand:(LDCommand)command enabledForNodes:mixed rootNode:_volume busy:NO]);
  }
  XCTAssertTrue([LDCommandRules isCommand:LDCommandCopyPath enabledForNodes:@[_file] rootNode:_volume busy:NO]);

  LDCustomCleanup *cleanup = [[LDCustomCleanup alloc] init];
  [cleanup setEnabled:YES];
  [cleanup setCommandLine:@"echo %p"];
  [cleanup setWorksForFiles:YES];
  [cleanup setWorksForDirectories:YES];
  [cleanup setWorksForMountPoints:YES];
  XCTAssertTrue([LDCommandRules isCleanup:cleanup enabledForNodes:@[_file] rootNode:_volume busy:NO]);
  XCTAssertFalse([LDCommandRules isCleanup:cleanup enabledForNodes:@[freeItem] rootNode:_volume busy:NO]);
}

#pragma mark - CSV

- (void)testCSVWritesTypeBitsAndReadsItemsBack
{
  [self update:_volume free:YES unknown:YES];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"lindirstat-space-%d.csv", getpid()]];
  NSError *error = nil;
  XCTAssertTrue([LDCSV writeTree:_volume toPath:path includeOwner:YES error:&error]);
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertTrue([text rangeOfString:@"\"/vol/<Free Space>\",0,0,0,300,\"\",1970-01-01T00:00:00Z,0x20000010,"].location != NSNotFound, @"%@", text);
  XCTAssertTrue([text rangeOfString:@"\"/vol/<Unknown>\",0,0,0,400,\"\",1970-01-01T00:00:00Z,0x20000020,"].location != NSNotFound, @"%@", text);

  LDFileNode *loaded = [LDCSV readTreeFromPath:path error:&error];
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  XCTAssertNotNil(loaded, @"%@", error);
  LDFileNode *freeItem = [LDSpaceItems spaceItemOfKind:LDFileNodeKindFreeSpace inVolume:loaded];
  LDFileNode *unknown = [LDSpaceItems spaceItemOfKind:LDFileNodeKindUnknown inVolume:loaded];
  XCTAssertEqualObjects(@"<Free Space>", [freeItem displayName]);
  XCTAssertEqual(300ULL, [freeItem aggregateAllocatedSize]);
  XCTAssertEqual(400ULL, [unknown aggregateAllocatedSize]);
  XCTAssertEqual(LDTestTotal, [loaded aggregateAllocatedSize]);
  XCTAssertEqual((NSUInteger)2, [loaded fileCount]);
}

#pragma mark - Treemap colors

- (void)testGraphColorsCarryWinDirStatFlags
{
  [self update:_volume free:YES unknown:YES];
  XCTAssertEqual(LDRGB(100, 100, 100) | LDRGBColorFlagDarker,
                 [LDTreemap colorForNode:[self freeItem] colorIndexes:@{}]);
  XCTAssertEqual(LDRGB(255, 255, 0) | LDRGBColorFlagLighter,
                 [LDTreemap colorForNode:[self unknownItem] colorIndexes:@{}]);
}

- (void)testFlaggedColorsAreRenderedEqualizedAndDarkerOrLighter
{
  LDTreemapOptions options = LDTreemapDefaultOptions();
  options.ambientLight = 1.0; // Flat colors, so one pixel tells the color.
  NSArray *kinds = @[@(LDFileNodeKindFreeSpace), @(LDFileNodeKindUnknown)];
  for (NSNumber *kind in kinds) {
    LDFileNode *root = [LDFileNode nodeWithPath:@"/vol" kind:LDFileNodeKindDirectory size:0];
    [root addChild:[LDFileNode spaceItemWithKind:(LDFileNodeKind)[kind intValue] allocatedSize:100]];
    [root recalculateAggregateSize];
    LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:root metric:LDSizeMetricPhysical
                                                       width:4 height:4 options:options];
    NSData *rgba = [treemap renderRGBAWithColorIndexes:@{}];
    const uint8_t *pixel = [rgba bytes];
    BOOL darker = [kind intValue] == LDFileNodeKindFreeSpace;
    LDRGBColor base = darker ? LDRGB(100, 100, 100) : LDRGB(255, 255, 0);
    LDRGBColor bright = [LDExtensionColor makeBrightColor:base brightness:0.6];
    double factor = (darker ? 0.88 * 0.66 : MIN(0.88 * 1.2, 1.0)) / 0.6;
    int red = (int)(LDRGBRed(bright) * factor);
    int green = (int)(LDRGBGreen(bright) * factor);
    int blue = (int)(LDRGBBlue(bright) * factor);
    [LDExtensionColor normalizeRed:&red green:&green blue:&blue];
    XCTAssertEqual(red, (int)pixel[0]);
    XCTAssertEqual(green, (int)pixel[1]);
    XCTAssertEqual(blue, (int)pixel[2]);
  }
}

@end
