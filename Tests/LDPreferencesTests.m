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
  for (NSNumber *prompt in [LDPreferences prompts]) {
    XCTAssertTrue([_preferences showsPrompt:(LDPrompt)[prompt intValue]]);
  }
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
  XCTAssertTrue([_preferences useAbsolutePercentages]);
  XCTAssertEqualWithAccuracy(16.0, [_preferences sizeProportionIndent], 0.01);
}

// WinDirStat 2.6 (db7af300) makes Percentage optional, shown by default.
- (void)testPercentageColumnIsOptional
{
  XCTAssertEqualObjects(LDColumnPercentage, [[LDPreferences optionalColumns] firstObject]);
  XCTAssertTrue([_preferences isColumnShown:LDColumnPercentage]);
  [_preferences setColumn:LDColumnPercentage shown:NO];
  XCTAssertFalse([_defaults boolForKey:@"ShowColumnPercentage"]);
  XCTAssertFalse([_preferences isColumnShown:LDColumnPercentage]);
}

// The folder list's header chooser and Preferences > Folder List share the
// ShowColumn settings.
- (void)testFolderListVisibilityIsTheFolderListPage
{
  XCTAssertTrue([_preferences isColumn:LDColumnFiles shownInList:LDColumnListFolders]);
  XCTAssertFalse([_preferences isColumn:LDColumnOwner shownInList:LDColumnListFolders]);
  [_preferences setColumn:LDColumnFiles shown:NO inList:LDColumnListFolders];
  XCTAssertFalse([_preferences isColumnShown:LDColumnFiles]);
  [_preferences setColumn:LDColumnOwner shown:YES];
  XCTAssertTrue([_preferences isColumn:LDColumnOwner shownInList:LDColumnListFolders]);
  XCTAssertEqual((NSUInteger)0, [[_defaults dictionaryForKey:@"HiddenColumns"] count]);
}

// The other lists show every column until one is hidden, each list on its own.
- (void)testOtherListsKeepTheirOwnVisibility
{
  XCTAssertTrue([_preferences isColumn:@"lastChange" shownInList:LDColumnListLargest]);
  [_preferences setColumn:@"lastChange" shown:NO inList:LDColumnListLargest];
  XCTAssertFalse([_preferences isColumn:@"lastChange" shownInList:LDColumnListLargest]);
  XCTAssertTrue([_preferences isColumn:@"lastChange" shownInList:LDColumnListSearch]);
  XCTAssertTrue([_preferences isColumnShown:LDColumnLastChange]);

  LDPreferences *reloaded = [[LDPreferences alloc] initWithUserDefaults:_defaults];
  XCTAssertFalse([reloaded isColumn:@"lastChange" shownInList:LDColumnListLargest]);

  [_preferences setColumn:@"lastChange" shown:YES inList:LDColumnListLargest];
  XCTAssertTrue([_preferences isColumn:@"lastChange" shownInList:LDColumnListLargest]);
  XCTAssertEqualObjects(@{}, [_defaults dictionaryForKey:@"HiddenColumns"]);
}

- (void)testHiddenColumnsResetAndChangeNotifications
{
  __block NSUInteger changes = 0;
  id observer = [[NSNotificationCenter defaultCenter] addObserverForName:LDPreferencesDidChangeNotification
                                                                  object:_preferences
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *note) {
    (void)note;
    changes++;
  }];
  [_preferences setColumn:@"files" shown:NO inList:LDColumnListExtensions];
  XCTAssertEqual((NSUInteger)1, changes);
  // Already hidden: nothing to change.
  [_preferences setColumn:@"files" shown:NO inList:LDColumnListExtensions];
  XCTAssertEqual((NSUInteger)1, changes);
  [[NSNotificationCenter defaultCenter] removeObserver:observer];

  [_preferences resetAll];
  XCTAssertTrue([_preferences isColumn:@"files" shownInList:LDColumnListExtensions]);
}

- (void)testAbsolutePercentagesPersist
{
  [_preferences setUseAbsolutePercentages:NO];
  XCTAssertFalse([_defaults boolForKey:@"UseAbsolutePercentages"]);
  XCTAssertFalse([_preferences useAbsolutePercentages]);
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

// WinDirStat 2.6 split the delete warning into one prompt per operation.
- (void)testPromptsAreSeparate
{
  [_preferences setShowsPrompt:NO forPrompt:LDPromptMoveToTrash];
  XCTAssertFalse([_preferences showsPrompt:LDPromptMoveToTrash]);
  XCTAssertTrue([_preferences showsPrompt:LDPromptDeletePermanently]);
  XCTAssertFalse([_defaults boolForKey:@"ShowDeleteToRecycleBinWarning"]);
  XCTAssertEqual((NSUInteger)6, [[LDPreferences prompts] count]);
}

// A pre-0.1.5 "Warn before deleting" that was turned off turns off the
// prompts it covered, once, and the old key goes away.
- (void)testOldDeleteWarningCarriesOver
{
  [_defaults setBool:NO forKey:@"ShowDeleteWarning"];
  LDPreferences *migrated = [[LDPreferences alloc] initWithUserDefaults:_defaults];
  XCTAssertFalse([migrated showsPrompt:LDPromptDeletePermanently]);
  XCTAssertFalse([migrated showsPrompt:LDPromptMoveToTrash]);
  XCTAssertFalse([migrated showsPrompt:LDPromptEmptyTrash]);
  XCTAssertTrue([migrated showsPrompt:LDPromptRemoveEmptyFolders]);
  XCTAssertNil([_defaults objectForKey:@"ShowDeleteWarning"]);
}

// WinDirStat's TreeMapShowFolderFrames (off) and
// TreeMapFolderFramesDrawThreshold (5, clamped to 3-128).
- (void)testFolderFramePreferences
{
  XCTAssertFalse([_preferences treemapShowFolderFrames]);
  XCTAssertEqual((NSInteger)5, [_preferences treemapFolderFramesDrawThreshold]);
  XCTAssertFalse([_preferences treemapOptions].showFolderFrames);
  XCTAssertEqual(5, [_preferences treemapOptions].folderFramesDrawThreshold);
  [_preferences setTreemapShowFolderFrames:YES];
  XCTAssertTrue([_preferences treemapOptions].showFolderFrames);
  [_defaults setInteger:1 forKey:@"TreeMapFolderFramesDrawThreshold"];
  XCTAssertEqual((NSInteger)3, [_preferences treemapFolderFramesDrawThreshold]);
  [_defaults setInteger:500 forKey:@"TreeMapFolderFramesDrawThreshold"];
  XCTAssertEqual((NSInteger)128, [_preferences treemapFolderFramesDrawThreshold]);
}

// WinDirStat 2.9: TreeMapSaturation (100, 0-100), Height up to 200, an Auto
// grid colour, the colour presets and the saved custom appearance.
- (void)testColorPresetPreferences
{
  XCTAssertEqual((NSInteger)100, [_preferences treemapSaturation]);
  XCTAssertEqual((NSInteger)0, [_preferences matchingTreemapPreset]);
  XCTAssertFalse([_preferences hasCustomTreemapPreset]);
  [_preferences setTreemapHeight:150];
  XCTAssertEqual((NSInteger)150, [_preferences treemapHeight]);
  [_preferences setTreemapHeight:500];
  XCTAssertEqual((NSInteger)200, [_preferences treemapHeight]);
  // That appearance matches no preset, so it is the custom one.
  XCTAssertEqual((NSInteger)-1, [_preferences matchingTreemapPreset]);
  XCTAssertTrue([_preferences hasCustomTreemapPreset]);

  XCTAssertTrue([_preferences applyTreemapPreset:LDTreemapPresetCalm]);
  XCTAssertEqual((NSInteger)LDTreemapPresetCalm, [_preferences matchingTreemapPreset]);
  XCTAssertEqual(LDTreemapGridColorAuto, [_preferences treemapGridColor]);
  XCTAssertEqual(LDTreemapGridColorAuto, [_preferences treemapOptions].gridColor);
  XCTAssertTrue([_preferences treemapGrid]);
  XCTAssertEqual((NSInteger)65, [_preferences treemapSaturation]);
  XCTAssertEqual((NSInteger)70, [_preferences treemapCushionShading]);

  // Custom brings back the appearance from before.
  XCTAssertTrue([_preferences applyTreemapPreset:LDTreemapPresetCount]);
  XCTAssertEqual((NSInteger)200, [_preferences treemapHeight]);
  XCTAssertFalse([_preferences treemapGrid]);
  XCTAssertEqual((NSInteger)-1, [_preferences matchingTreemapPreset]);

  [_preferences setTreemapGridColor:0x123456];
  XCTAssertEqual((uint32_t)0x123456, [_preferences treemapGridColor]);
  XCTAssertTrue([_preferences applyTreemapPreset:LDTreemapPresetHighContrast]);
  XCTAssertEqual((uint32_t)0x000000, [_preferences treemapGridColor]);
  XCTAssertFalse([_preferences applyTreemapPreset:99]);
}

@end


