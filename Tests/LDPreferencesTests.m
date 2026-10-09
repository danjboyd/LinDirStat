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
