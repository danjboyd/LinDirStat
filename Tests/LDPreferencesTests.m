#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "LDPreferences.h"

@interface LDPreferencesTests : XCTestCase
{
  NSUserDefaults *_defaults;
  LDPreferences *_preferences;
}
@end

@implementation LDPreferencesTests

- (void)setUp
{
  [super setUp];
  // The test runner's own defaults domain (xctest), cleared around each test.
  _defaults = [NSUserDefaults standardUserDefaults];
  _preferences = [[LDPreferences alloc] initWithUserDefaults:_defaults];
  [_preferences resetAll];
}

- (void)tearDown
{
  [_preferences resetAll];
  [super tearDown];
}

- (void)testDefaultsFollowWinDirStat
{
  XCTAssertTrue([_preferences showDeleteWarning]);
  XCTAssertTrue([_preferences pacmanAnimation]);
  XCTAssertEqual((NSUInteger)50, [_preferences largeFileCount]);
  XCTAssertEqual((NSUInteger)4, [_preferences scanningThreads]);
  XCTAssertEqual((NSInteger)88, [_preferences treemapBrightness]);
  XCTAssertTrue([_preferences excludeMountPoints]);
  XCTAssertFalse([_preferences scanForDuplicates]);
  XCTAssertTrue([_preferences isColumnShown:LDColumnFiles]);
  XCTAssertFalse([_preferences isColumnShown:LDColumnOwner]);
  XCTAssertFalse([_preferences showFreeSpace]);
  XCTAssertFalse([_preferences showUnknown]);
}

- (void)testShowFreeSpaceAndUnknownPersist
{
  [_preferences setShowFreeSpace:YES];
  [_preferences setShowUnknown:YES];
  XCTAssertTrue([_defaults boolForKey:@"ShowFreeSpace"]);
  XCTAssertTrue([_defaults boolForKey:@"ShowUnknown"]);
  [_preferences setShowUnknown:NO];
  XCTAssertFalse([_preferences showUnknown]);
  XCTAssertTrue([_preferences showFreeSpace]);
}

- (void)testChromeAndColumnDefaultsFollowWinDirStat
{
  XCTAssertTrue([_preferences automaticallyResizeColumns]);
  XCTAssertTrue([_preferences showToolBar]);
  XCTAssertTrue([_preferences showStatusBar]);
  XCTAssertFalse([_preferences largeToolBar]);
  XCTAssertEqual((uint32_t)0x000000, [_preferences treemapGridColor]);
  XCTAssertEqual((uint32_t)0xffffff, [_preferences treemapHighlightColor]);
  XCTAssertEqual((NSUInteger)8, [_preferences fileTreeColorCount]);
  XCTAssertEqual((uint32_t)0x1a5fb4, [_preferences fileTreeColorAtIndex:0]);
  XCTAssertEqual((uint32_t)0xf6d32d, [_preferences fileTreeColorAtIndex:7]);
}

- (void)testChromeAndColorsRoundTrip
{
  [_preferences setAutomaticallyResizeColumns:NO];
  [_preferences setShowToolBar:NO];
  [_preferences setShowStatusBar:NO];
  [_preferences setLargeToolBar:YES];
  [_preferences setTreemapGridColor:0x123456];
  [_preferences setTreemapHighlightColor:0xff00ff7f];
  [_preferences setFileTreeColor:0xabcdef atIndex:3];
  LDPreferences *reloaded = [[LDPreferences alloc] initWithUserDefaults:_defaults];
  XCTAssertFalse([reloaded automaticallyResizeColumns]);
  XCTAssertFalse([reloaded showToolBar]);
  XCTAssertFalse([reloaded showStatusBar]);
  XCTAssertTrue([reloaded largeToolBar]);
  XCTAssertEqual((uint32_t)0x123456, [reloaded treemapGridColor]);
  // Only the 24 colour bits are kept.
  XCTAssertEqual((uint32_t)0x00ff7f, [reloaded treemapHighlightColor]);
  XCTAssertEqual((uint32_t)0xabcdef, [reloaded fileTreeColorAtIndex:3]);
  XCTAssertEqual((uint32_t)0, [reloaded fileTreeColorAtIndex:8]);
  [reloaded resetAll];
  XCTAssertEqual((uint32_t)0xe5a50a, [reloaded fileTreeColorAtIndex:3]);
}

- (void)testLevelColorsRepeatAfterTheCount
{
  [_preferences setFileTreeColorCount:0];
  XCTAssertEqual((NSUInteger)1, [_preferences fileTreeColorCount]);
  [_preferences setFileTreeColorCount:20];
  XCTAssertEqual((NSUInteger)8, [_preferences fileTreeColorCount]);
  [_preferences setFileTreeColorCount:3];
  XCTAssertEqual([_preferences fileTreeColorAtIndex:1], [_preferences fileTreeColorForDepth:4]);
  XCTAssertEqual([_preferences fileTreeColorAtIndex:0], [_preferences fileTreeColorForDepth:3]);
}

- (void)testTreemapOptionsCollectTheSettings
{
  [_preferences setTreemapStyle:1];
  [_preferences setTreemapGrid:YES];
  [_preferences setTreemapGridColor:0x00ff00];
  [_preferences setTreemapBrightness:50];
  LDTreemapOptions options = [_preferences treemapOptions];
  XCTAssertEqual(LDTreemapStyleSequoiaView, options.style);
  XCTAssertTrue(options.grid);
  XCTAssertEqual((LDRGBColor)0x00ff00, options.gridColor);
  XCTAssertEqualWithAccuracy(0.5, options.brightness, 0.0001);
  // Reset keeps the colours, as WinDirStat's does.
  [_preferences resetTreemapOptions];
  XCTAssertEqual((uint32_t)0x00ff00, [_preferences treemapGridColor]);
  XCTAssertFalse([_preferences treemapGrid]);
}

- (void)testValuesAreClamped
{
  [_preferences setScanningThreads:99];
  XCTAssertEqual((NSUInteger)16, [_preferences scanningThreads]);
  [_preferences setTreemapLightSourceX:-500];
  XCTAssertEqual((NSInteger)-100, [_preferences treemapLightSourceX]);
}

- (void)testMinimumSizeUsesBinaryUnits
{
  [_preferences setMinimumFileSize:3];
  [_preferences setMinimumFileSizeUnit:LDSizeUnitMiB];
  XCTAssertEqual(3ULL * 1024 * 1024, [_preferences minimumFileSizeInBytes]);
}

- (void)testFolderHistoryIsMostRecentFirstAndLimited
{
  [_preferences setFolderHistoryCount:2];
  [_preferences addFolderToHistory:@"/a"];
  [_preferences addFolderToHistory:@"/b"];
  [_preferences addFolderToHistory:@"/a"];
  [_preferences addFolderToHistory:@"/c"];
  XCTAssertEqualObjects((@[@"/c", @"/a"]), [_preferences folderHistory]);
}

- (void)testCustomCleanupsRoundTripAndNormalize
{
  NSArray *cleanups = [_preferences customCleanups];
  XCTAssertEqual((NSUInteger)10, [cleanups count]);
  LDCustomCleanup *first = [cleanups objectAtIndex:0];
  XCTAssertEqualObjects(@"Custom Cleanup #0", [first displayTitleForSlot:0]);
  [first setEnabled:YES];
  [first setTitle:@"Compress"];
  [first setWorksForFiles:YES];
  [first setRecurseIntoSubdirectories:YES];   // needs folders: dropped
  [first setRefreshPolicy:LDRefreshPolicyEntry]; // needs waiting: dropped
  [_preferences setCustomCleanups:cleanups];

  LDCustomCleanup *stored = [[_preferences customCleanups] objectAtIndex:0];
  XCTAssertEqualObjects(@"Compress", [stored title]);
  XCTAssertTrue([stored isEnabled]);
  XCTAssertFalse([stored recurseIntoSubdirectories]);
  XCTAssertEqual(LDRefreshPolicyNone, [stored refreshPolicy]);

  [stored setWorksForDirectories:YES];
  [stored setRecurseIntoSubdirectories:YES];
  [stored normalize];
  XCTAssertTrue([stored waitForCompletion]);
}

@end
