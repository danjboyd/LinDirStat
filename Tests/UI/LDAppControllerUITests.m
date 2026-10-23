#import <AppKit/AppKit.h>
#include <sys/stat.h>
#include <sys/time.h>
#import <XCTest/XCTest.h>
#if defined(GNUSTEP)
#import <GNUstepGUI/GSFontInfo.h>
#endif
#import "AppController.h"
#import "AppController+Private.h"
#import "LDCommandRules.h"
#import "LDExtensionStats.h"
#import "LDFileOperations.h"
#import "LDFileWatcher.h"
#import "LDHardLinks.h"
#import "LDPreferences.h"
#import "LDOptionsWindowController.h"
#import "LDScanSession.h"
#import "LDSearch.h"
#import "LDSizeFormatter.h"
#import "LDSpaceItems.h"
#import "LDTreemapView.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// The real AppController and its window, driven the way the user's actions
// arrive (row selection, delegate calls, menu actions) without modal
// dialogs. scripts/run-ui-tests.sh runs these on a private Xvfb with a
// private GNUSTEP_HOME (so private defaults), XDG_DATA_HOME (so a private trash) and
// TMPDIR (so the trees below are throwaway folders on the trash's
// filesystem). On macOS, scripts/run-ui-tests-macos.sh runs them with a
// private TMPDIR; the defaults are the xctest tool's domain, which the
// script saves and restores, and the test that trashes is Linux only (the
// trash would be the user's).

@interface AppController (UITestAccess)
- (void)setUpMainWindow;
- (void)beginScanPaths:(NSArray *)paths;
- (void)finishAsyncScan;
- (BOOL)validateAction:(SEL)action;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)toggleFreeSpace:(id)sender;
- (void)toggleUnknown:(id)sender;
- (void)toggleFileTypes:(id)sender;
- (void)toggleTreemap:(id)sender;
- (void)toggleLogicalSize:(id)sender;
- (void)toggleAbsolutePercentages:(id)sender;
- (void)stopScan:(id)sender;
- (void)openPath:(id)sender;
- (void)treemapView:(LDTreemapView *)view didSelectNode:(LDFileNode *)node;
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item;
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;
@end

// What a click on a cell does.
@interface LDTreemapView (UITestAccess)
- (void)selectNodeAndNotify:(LDFileNode *)node;
@end

@interface LDUITestController : AppController
{
  NSUInteger _scansFinished;
}
@end

@implementation LDUITestController

- (void)finishAsyncScan
{
  [super finishAsyncScan];
  _scansFinished++;
}

- (NSUInteger)scansFinished { return _scansFinished; }
- (NSWindow *)window { return _window; }
- (LDOutlineView *)tree { return _directoryTable; }
- (NSTableView *)extensionTable { return _extensionTable; }
- (NSArray *)extensionRows { return _extensionRows; }
- (NSScrollView *)extensionScroll { return _extensionScroll; }
- (NSSplitView *)topSplit { return _topSplit; }
- (NSSplitView *)mainSplit { return _mainSplit; }
- (LDTreemapView *)treemap { return _treemapView; }
- (NSTextField *)statusField { return _statusField; }
- (NSTextField *)selectionField { return _selectionField; }
- (LDFileNode *)root { return _rootNode; }
- (NSTabView *)fileTabs { return _fileTabs; }
- (NSTabViewItem *)allFilesTab { return _allFilesTab; }
- (NSTabViewItem *)largestTab { return _largestTab; }
- (NSTabViewItem *)duplicatesTab { return _duplicatesTab; }
- (NSTabViewItem *)searchTab { return _searchTab; }
- (NSTabViewItem *)watcherTab { return _watcherTab; }
- (NSTableView *)largestTable { return _largestTable; }
- (NSTableView *)searchTable { return _searchTable; }
- (NSOutlineView *)duplicatesTable { return _duplicatesTable; }
- (NSTableView *)watcherTable { return _watcherTable; }
- (NSArray *)largestFiles { return _largestFiles; }
- (NSArray *)searchRows { return _searchRows; }
- (NSArray *)duplicateGroups { return _duplicateGroups; }
- (NSArray *)watcherRows { return _watcherRows; }

// Timers retain the controller; observers and background work would outlive
// the test.
- (void)tearDownForTest
{
  [_busyTimer invalidate];
  _busyTimer = nil;
  [_memoryTimer invalidate];
  _memoryTimer = nil;
  [_scanSession cancel];
  [_refreshSession cancel];
  [_fileWatcher stop];
  _fileWatcher = nil;
  [_duplicateFinder cancel];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_window orderOut:nil];
}

@end

@interface LDAppControllerUITests : XCTestCase
{
  LDUITestController *_controller;
  NSString *_workRoot;
  NSString *_tree;
}
@end

@implementation LDAppControllerUITests

#pragma mark - Harness

// The installed libs-gui keeps the backend's default font names without
// retaining them (fixed upstream by "Fix: retain the default font names for
// the font roles"); the app survives because its first font is made in
// main()'s pool, but each test drains its own pools. Naming the role fonts
// in the registration domain keeps NSFont off those dangling names.
+ (void)initialize
{
  if (self != [LDAppControllerUITests class] || ![self isPrivateEnvironment]) {
    return;
  }
  [NSApplication sharedApplication];
#if defined(GNUSTEP)
  GSFontEnumerator *fonts = [GSFontEnumerator sharedEnumerator];
  [[NSUserDefaults standardUserDefaults] registerDefaults:@{
    @"NSFont": [[fonts defaultSystemFontName] copy],
    @"NSBoldFont": [[fonts defaultBoldSystemFontName] copy],
    @"NSUserFixedPitchFont": [[fonts defaultFixedPitchFontName] copy],
  }];
#endif
}

+ (NSString *)defaultsRoot
{
#if defined(GNUSTEP)
  return GSDefaultsRootForUser(NSUserName());
#else
  // The domain the defaults are written to: the host process's.
  return [[NSBundle mainBundle] bundleIdentifier];
#endif
}

// Only under scripts/run-ui-tests.sh (or run-ui-tests-macos.sh): the tests
// write preferences and use the trash, which must never be the user's.
+ (BOOL)isPrivateEnvironment
{
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *root = [environment objectForKey:@"LINDIRSTAT_UI_TESTS_ROOT"];
  if (![[environment objectForKey:@"LINDIRSTAT_UI_TESTS"] isEqualToString:@"1"] || [root length] == 0
      || ![[environment objectForKey:@"TMPDIR"] hasPrefix:root]) {
    return NO;
  }
#if defined(__APPLE__)
  // macOS defaults cannot be moved: they are the host's domain, which must
  // be the one the script saves and restores, never LinDirStat's.
  NSString *domain = [self defaultsRoot];
  return [domain length] > 0 && ![domain isEqualToString:@"io.github.danjboyd.LinDirStat"]
    && [domain isEqualToString:[environment objectForKey:@"LINDIRSTAT_UI_TESTS_DEFAULTS_DOMAIN"]];
#else
  if (![[environment objectForKey:@"XDG_DATA_HOME"] hasPrefix:root]) {
    return NO;
  }
  // Where the user defaults really go.
  return [[self defaultsRoot] hasPrefix:root];
#endif
}

- (void)writeFile:(NSString *)relative size:(NSUInteger)size seed:(unsigned)seed
{
  NSString *path = [_tree stringByAppendingPathComponent:relative];
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  NSMutableData *data = [NSMutableData dataWithLength:size];
  unsigned char *bytes = [data mutableBytes];
  unsigned state = seed * 2654435761u + 1;
  for (NSUInteger i = 0; i < size; i++) {
    state = state * 1103515245u + 12345u;
    bytes[i] = (unsigned char)(state >> 16);
  }
  XCTAssertTrue([data writeToFile:path atomically:NO]);
}

- (NSString *)pathOf:(NSString *)relative
{
  return [relative length] ? [_tree stringByAppendingPathComponent:relative] : _tree;
}

- (NSData *)pathDataOf:(NSString *)relative
{
  const char *bytes = [[self pathOf:relative] fileSystemRepresentation];
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

- (LDFileNode *)node:(NSString *)relative
{
  return [_controller nodeForPathData:[self pathDataOf:relative]];
}

- (void)setUp
{
  [super setUp];
  if (![[self class] isPrivateEnvironment]) {
    // Under the runner a leak of the environment is a failure, not a skip.
    if ([[[[NSProcessInfo processInfo] environment] objectForKey:@"LINDIRSTAT_UI_TESTS"] isEqualToString:@"1"]) {
      XCTFail(@"not private: defaults in %@", [[self class] defaultsRoot]);
    } else {
      NSLog(@"LDAppControllerUITests: skipped; run scripts/run-ui-tests.sh (private display, defaults and trash)");
    }
    return;
  }
  [NSApplication sharedApplication];
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences resetAll];
  // Confirmations are modal panels.
  for (NSNumber *prompt in [LDPreferences prompts]) {
    [preferences setShowsPrompt:NO forPrompt:(LDPrompt)[prompt intValue]];
  }

  // TMPDIR itself: gnustep-base's NSTemporaryDirectory() may pick another.
  NSString *temporary = [[[NSProcessInfo processInfo] environment] objectForKey:@"TMPDIR"];
  NSString *template = [temporary stringByAppendingPathComponent:@"ui-tree.XXXXXX"];
  char *buffer = strdup([template fileSystemRepresentation]);
  XCTAssertTrue(mkdtemp(buffer) != NULL);
  _workRoot = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer length:strlen(buffer)];
  free(buffer);
  _tree = [_workRoot stringByAppendingPathComponent:@"tree"];
  [self writeFile:@"a/a1.txt" size:3000 seed:1];
  [self writeFile:@"a/a2.log" size:5000 seed:2];
  [self writeFile:@"a/sub/deep.txt" size:2000 seed:3];
  [self writeFile:@"b/b1.txt" size:40000 seed:4];
  [self writeFile:@"c.bin" size:12000 seed:5];

  _controller = [[LDUITestController alloc] init];
  [_controller applicationWillFinishLaunching:[NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:NSApp]];
  [_controller setUpMainWindow];
}

- (void)tearDown
{
  [_controller tearDownForTest];
  // The app never releases its controller; releasing one that holds a
  // scanned tree crashes while the views and the tree are torn down, so the
  // finished ones are kept.
  static NSMutableArray *finishedControllers = nil;
  if (_controller) {
    if (!finishedControllers) {
      finishedControllers = [NSMutableArray array];
    }
    [finishedControllers addObject:_controller];
  }
  _controller = nil;
  if (_workRoot) {
    [[NSFileManager defaultManager] removeItemAtPath:_workRoot error:NULL];
  }
  [super tearDown];
}

- (BOOL)waitFor:(BOOL (^)(void))condition seconds:(NSTimeInterval)seconds
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while (!condition()) {
    if ([deadline timeIntervalSinceNow] <= 0) {
      return NO;
    }
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  return YES;
}

- (void)spin:(NSTimeInterval)seconds
{
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (BOOL)scanPaths:(NSArray *)paths
{
  LDUITestController *controller = _controller;
  NSUInteger before = [controller scansFinished];
  [controller beginScanPaths:paths];
  BOOL done = [self waitFor:^BOOL {
    return [controller scansFinished] > before && ![controller isBusy];
  } seconds:20.0];
  XCTAssertTrue(done, @"scan of %@ finished", paths);
  return done;
}

- (BOOL)scanTree
{
  return [self scanPaths:@[_tree]];
}

- (BOOL)waitUntilIdle
{
  LDUITestController *controller = _controller;
  BOOL done = [self waitFor:^BOOL { return ![controller isBusy]; } seconds:20.0];
  XCTAssertTrue(done, @"refresh or file operation finished");
  return done;
}

- (void)revealInTree:(LDFileNode *)node
{
  NSMutableArray *ancestors = [NSMutableArray array];
  for (LDFileNode *cursor = [node parent]; cursor; cursor = [cursor parent]) {
    [ancestors insertObject:cursor atIndex:0];
  }
  for (LDFileNode *ancestor in ancestors) {
    [[_controller tree] expandItem:ancestor];
  }
}

// As a click does: the tree gets the focus and its rows are selected.
- (void)selectInTree:(NSArray *)nodes
{
  NSOutlineView *tree = [_controller tree];
  [[_controller fileTabs] selectTabViewItem:[_controller allFilesTab]];
  [[_controller window] makeFirstResponder:tree];
  NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
  for (LDFileNode *node in nodes) {
    [self revealInTree:node];
  }
  for (LDFileNode *node in nodes) {
    NSInteger row = [tree rowForItem:node];
    XCTAssertTrue(row >= 0, @"%@ has a row", [node path]);
    if (row >= 0) {
      [rows addIndex:(NSUInteger)row];
    }
  }
  [tree selectRowIndexes:rows byExtendingSelection:NO];
}

- (NSArray *)treeSelection
{
  NSOutlineView *tree = [_controller tree];
  NSMutableArray *items = [NSMutableArray array];
  NSIndexSet *rows = [tree selectedRowIndexes];
  for (NSUInteger row = [rows firstIndex]; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
    [items addObject:[tree itemAtRow:(NSInteger)row]];
  }
  return items;
}

- (void)selectRow:(NSInteger)row inList:(NSTableView *)list
{
  [[_controller window] makeFirstResponder:list];
  [list selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (NSString *)physicalSizeLabel:(unsigned long long)bytes
{
  return [@"Physical Size: " stringByAppendingString:[LDSizeFormatter stringForBytes:bytes]];
}

- (unsigned long long)allocatedBytesOnDisk:(NSString *)relative
{
  struct stat info;
  XCTAssertEqual(0, lstat([[self pathOf:relative] fileSystemRepresentation], &info));
  return (unsigned long long)info.st_blocks * 512ULL;
}

- (NSArray *)extensionKeys
{
  NSMutableArray *keys = [NSMutableArray array];
  for (LDExtensionStats *stats in [_controller extensionRows]) {
    [keys addObject:[stats extensionKey]];
  }
  return keys;
}

- (NSString *)key:(NSString *)filename
{
  return [LDExtensionStats extensionKeyForFilename:filename];
}

- (BOOL)allInTree:(NSArray *)nodes
{
  for (LDFileNode *node in nodes) {
    if (![[_controller root] isAncestorOf:node]) {
      return NO;
    }
  }
  return YES;
}

#pragma mark - Selection sync

// A build run from the tree can't update itself, so it doesn't offer to.
- (void)testUnpackagedBuildDoesNotOfferUpdates
{
  NSMenu *mainMenu = [NSApp mainMenu];
  XCTAssertNotNil(mainMenu);
  for (NSMenuItem *top in [mainMenu itemArray]) {
    for (NSMenuItem *item in [[top submenu] itemArray]) {
      XCTAssertFalse([item action] == @selector(checkForUpdates:), @"%@ > %@", [top title], [item title]);
    }
  }
}

// The controller owns the main window. Released when closed as well, closing
// it (its close button, or Alt+F4 under GNOME Shell) freed it twice and the
// app crashed as it quit.
- (void)testMainWindowIsNotReleasedWhenClosed
{
  XCTAssertFalse([[_controller window] isReleasedWhenClosed]);
}

- (void)testTreeSelectionSelectsInTreemap
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *b = [self node:@"b"];
  XCTAssertNotNil(b);
  [self selectInTree:@[b]];

  XCTAssertEqual(b, [[_controller treemap] selectedNode]);
  XCTAssertEqualObjects(@[b], [_controller selectedNodes]);
  XCTAssertTrue([[[_controller statusField] stringValue] hasPrefix:[self pathOf:@"b"]]);
  XCTAssertEqualObjects([self physicalSizeLabel:[self allocatedBytesOnDisk:@"b/b1.txt"]], [[_controller selectionField] stringValue]);
}

- (void)testTreemapClickRevealsAndSelectsInTree
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *deep = [self node:@"a/sub/deep.txt"];
  LDTreemapView *treemap = [_controller treemap];
  XCTAssertFalse([[_controller tree] isItemExpanded:[self node:@"a"]]);

  [treemap setSelectedNode:deep];
  [_controller treemapView:treemap didSelectNode:deep];

  XCTAssertTrue([[_controller tree] isItemExpanded:[self node:@"a"]]);
  XCTAssertTrue([[_controller tree] isItemExpanded:[self node:@"a/sub"]]);
  XCTAssertEqualObjects(@[deep], [self treeSelection]);
  XCTAssertEqual(deep, [treemap selectedNode]);
  XCTAssertEqualObjects(@[deep], [_controller selectedNodes]);
  XCTAssertTrue([[[_controller statusField] stringValue] hasPrefix:[self pathOf:@"a/sub/deep.txt"]]);
}

- (void)testExtensionRowHighlightsTreemap
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  NSUInteger index = [[self extensionKeys] indexOfObject:[self key:@"x.log"]];
  XCTAssertTrue(index != NSNotFound);
  [self selectRow:(NSInteger)index inList:[_controller extensionTable]];

  XCTAssertEqualObjects([self key:@"x.log"], [[_controller treemap] highlightedExtensionKey]);
  XCTAssertTrue([[[_controller statusField] stringValue] hasPrefix:@"*.log"]);

  // Selecting in the tree goes back to the selection frame.
  [self selectInTree:@[[self node:@"c.bin"]]];
  XCTAssertNil([[_controller treemap] highlightedExtensionKey]);
  XCTAssertEqual([self node:@"c.bin"], [[_controller treemap] selectedNode]);
}

// The size pane describes the tree's selection; with an extension selected
// it is empty (WinDirStat, #26), and it comes back with the next selection.
- (void)testExtensionSelectionClearsSelectionSize
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *c = [self node:@"c.bin"];
  NSString *cSize = [self physicalSizeLabel:[self allocatedBytesOnDisk:@"c.bin"]];
  [self selectInTree:@[c]];
  XCTAssertEqualObjects(cSize, [[_controller selectionField] stringValue]);

  NSUInteger index = [[self extensionKeys] indexOfObject:[self key:@"x.log"]];
  XCTAssertTrue(index != NSNotFound);
  [self selectRow:(NSInteger)index inList:[_controller extensionTable]];
  XCTAssertTrue([[[_controller statusField] stringValue] hasPrefix:@"*.log"]);
  XCTAssertEqualObjects(@"", [[_controller selectionField] stringValue]);

  // Back in the tree.
  [self selectInTree:@[[self node:@"b"]]];
  XCTAssertEqualObjects([self physicalSizeLabel:[self allocatedBytesOnDisk:@"b/b1.txt"]], [[_controller selectionField] stringValue]);

  // A treemap click after an extension (what -mouseDown: does). The row is
  // still selected from before, so select it afresh.
  [[_controller extensionTable] deselectAll:nil];
  [self selectRow:(NSInteger)index inList:[_controller extensionTable]];
  XCTAssertEqualObjects(@"", [[_controller selectionField] stringValue]);
  LDTreemapView *treemap = [_controller treemap];
  [treemap selectNodeAndNotify:c];
  XCTAssertNil([treemap highlightedExtensionKey]);
  XCTAssertEqualObjects(cSize, [[_controller selectionField] stringValue]);
}

- (void)testMultipleSelectionSumsTopmostPhysicalSizes
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *b = [self node:@"b"];
  LDFileNode *c = [self node:@"c.bin"];
  [self selectInTree:@[b, c]];
  NSArray *selected = [_controller selectedNodes];
  XCTAssertEqual((NSUInteger)2, [selected count]);
  XCTAssertTrue([selected containsObject:b] && [selected containsObject:c]);
  unsigned long long expected = [self allocatedBytesOnDisk:@"b/b1.txt"] + [self allocatedBytesOnDisk:@"c.bin"];
  XCTAssertEqualObjects([self physicalSizeLabel:expected], [[_controller selectionField] stringValue]);

  // A folder and something inside it count once.
  LDFileNode *a = [self node:@"a"];
  [self selectInTree:@[a, [self node:@"a/a1.txt"]]];
  XCTAssertEqual((NSUInteger)2, [[_controller selectedNodes] count]);
  XCTAssertEqualObjects([self physicalSizeLabel:[a aggregateAllocatedSize]], [[_controller selectionField] stringValue]);

  [[_controller tree] deselectAll:nil];
  [[_controller treemap] setSelectedNode:nil];
  XCTAssertEqualObjects(@"", [[_controller selectionField] stringValue]);
}

- (void)testLargestFilesAndSearchResultsDriveTreemap
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  [[_controller fileTabs] selectTabViewItem:[_controller largestTab]];
  XCTAssertEqual([_controller largestTable], [_controller activeFileList]);
  XCTAssertEqual((NSUInteger)5, [[_controller largestFiles] count]);
  LDFileNode *largest = [[_controller largestFiles] objectAtIndex:0];
  XCTAssertEqual([self node:@"b/b1.txt"], largest);
  [self selectRow:0 inList:[_controller largestTable]];
  XCTAssertEqual(largest, [[_controller treemap] selectedNode]);
  XCTAssertEqualObjects(@[largest], [_controller selectedNodes]);
  XCTAssertEqualObjects([self physicalSizeLabel:[self allocatedBytesOnDisk:@"b/b1.txt"]], [[_controller selectionField] stringValue]);

  [_controller showSearchResultsForOptions:[LDSearchOptions optionsWithTerm:@"deep"]];
  XCTAssertEqual([_controller searchTable], [_controller activeFileList]);
  XCTAssertEqual((NSUInteger)1, [[_controller searchRows] count]);
  XCTAssertEqualObjects(@"Search Results (1)", [[_controller searchTab] label]);
  [self selectRow:0 inList:[_controller searchTable]];
  LDFileNode *deep = [self node:@"a/sub/deep.txt"];
  XCTAssertEqual(deep, [[_controller treemap] selectedNode]);
  XCTAssertEqualObjects(@[deep], [_controller selectedNodes]);

  // The treemap's own selection counts while it has the focus.
  [[_controller window] makeFirstResponder:[_controller treemap]];
  [[_controller treemap] setSelectedNode:[self node:@"c.bin"]];
  XCTAssertEqualObjects(@[[self node:@"c.bin"]], [_controller selectedNodes]);
}

// WinDirStat 2.8: a whole duplicate group selected keeps the first copy and
// makes the others hard links to it; only from the Duplicates list.
- (void)testDeduplicateWithHardlink
{
  if (!_controller) {
    return;
  }
  [self writeFile:@"dup-one.dat" size:8000 seed:9];
  [self writeFile:@"a/dup-two.dat" size:8000 seed:9];
  [[LDPreferences sharedPreferences] setScanForDuplicates:YES];
  if (![self scanTree]) {
    return;
  }
  LDUITestController *controller = _controller;
  XCTAssertTrue([self waitFor:^BOOL { return ![controller isFindingDuplicates]; } seconds:20.0]);
  [self selectInTree:@[[self node:@"dup-one.dat"], [self node:@"a/dup-two.dat"]]];
  XCTAssertFalse([_controller validateAction:@selector(deduplicateWithHardLinks:)]);

  [[_controller fileTabs] selectTabViewItem:[_controller duplicatesTab]];
  [self selectRow:0 inList:[_controller duplicatesTable]];
  XCTAssertTrue([_controller validateAction:@selector(deduplicateWithHardLinks:)]);
  [_controller deduplicateWithHardLinks:nil];
  if (![self waitUntilIdle]) {
    return;
  }
  struct stat one, two;
  XCTAssertEqual(0, stat([[self pathOf:@"dup-one.dat"] fileSystemRepresentation], &one));
  XCTAssertEqual(0, stat([[self pathOf:@"a/dup-two.dat"] fileSystemRepresentation], &two));
  XCTAssertEqual(one.st_ino, two.st_ino);
  XCTAssertEqual((nlink_t)2, one.st_nlink);
}

- (void)testDuplicateGroupDrivesTreemapAndSelection
{
  if (!_controller) {
    return;
  }
  [self writeFile:@"dup-one.dat" size:8000 seed:9];
  [self writeFile:@"a/dup-two.dat" size:8000 seed:9];
  [[LDPreferences sharedPreferences] setScanForDuplicates:YES];
  if (![self scanTree]) {
    return;
  }
  LDUITestController *controller = _controller;
  XCTAssertTrue([self waitFor:^BOOL { return ![controller isFindingDuplicates]; } seconds:20.0]);
  XCTAssertTrue([[[_controller fileTabs] tabViewItems] containsObject:[_controller duplicatesTab]]);
  XCTAssertEqual((NSUInteger)1, [[_controller duplicateGroups] count]);

  [[_controller fileTabs] selectTabViewItem:[_controller duplicatesTab]];
  [self selectRow:0 inList:[_controller duplicatesTable]];
  LDFileNode *one = [self node:@"dup-one.dat"];
  LDFileNode *two = [self node:@"a/dup-two.dat"];
  NSArray *selected = [_controller selectedNodes];
  XCTAssertEqual((NSUInteger)2, [selected count]);
  XCTAssertTrue([selected containsObject:one] && [selected containsObject:two]);
  XCTAssertTrue([[_controller treemap] selectedNode] == one || [[_controller treemap] selectedNode] == two);
  XCTAssertEqualObjects([self physicalSizeLabel:[one allocatedSize] + [two allocatedSize]], [[_controller selectionField] stringValue]);

  // A file row of the group.
  NSOutlineView *duplicates = [_controller duplicatesTable];
  [duplicates expandItem:[duplicates itemAtRow:0]];
  [self selectRow:1 inList:duplicates];
  id file = [duplicates itemAtRow:1];
  XCTAssertEqualObjects(@[file], [_controller selectedNodes]);
  XCTAssertEqual(file, [[_controller treemap] selectedNode]);
}

- (void)testFileWatcherRowDrivesTreemap
{
  if (!_controller || ![LDFileWatcher isSupported] || ![self scanTree]) {
    return;
  }
  XCTAssertTrue([_controller validateAction:@selector(toggleFileWatcher:)]);
  [_controller toggleFileWatcher:nil];
  XCTAssertTrue([_controller isFileWatcherOn]);
  XCTAssertEqual([_controller watcherTable], [_controller activeFileList]);
  [self spin:0.2];

  NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:[self pathOf:@"a/a1.txt"]];
  [handle seekToEndOfFile];
  [handle writeData:[@"more" dataUsingEncoding:NSUTF8StringEncoding]];
  [handle closeFile];

  LDUITestController *controller = _controller;
  NSString *path = [self pathOf:@"a/a1.txt"];
  __block NSUInteger row = NSNotFound;
  BOOL seen = [self waitFor:^BOOL {
    NSArray *rows = [controller watcherRows];
    for (NSUInteger i = 0; i < [rows count]; i++) {
      if ([[[rows objectAtIndex:i] path] isEqualToString:path]) {
        row = i;
        return YES;
      }
    }
    return NO;
  } seconds:5.0];
  XCTAssertTrue(seen, @"the watcher listed the change");
  if (seen) {
    [self selectRow:(NSInteger)row inList:[_controller watcherTable]];
    LDFileNode *a1 = [self node:@"a/a1.txt"];
    XCTAssertEqual(a1, [[_controller treemap] selectedNode]);
    XCTAssertEqualObjects(@[a1], [_controller selectedNodes]);
  }

  [_controller toggleFileWatcher:nil];
  XCTAssertFalse([_controller isFileWatcherOn]);
  XCTAssertFalse([[[_controller fileTabs] tabViewItems] containsObject:[_controller watcherTab]]);
  XCTAssertEqual([_controller tree], (LDOutlineView *)[_controller activeFileList]);
}

#pragma mark - Refresh engine

- (void)testAddToExclusionFilterDropsItemsAndExtensions
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [self revealInTree:[self node:@"a/a2.log"]];
  [self selectInTree:@[[self node:@"a/a2.log"], [self node:@"b"]]];
  XCTAssertTrue([_controller validateAction:@selector(excludeItem:)]);
  [_controller excludeItem:nil];
  if (![self waitUntilIdle]) {
    return;
  }
  // A file's name, a folder's whole path.
  XCTAssertEqualObjects(@"a2.log", [preferences excludedFilePatterns]);
  XCTAssertEqualObjects([self pathOf:@"b"], [preferences excludedFolderPatterns]);
  XCTAssertNil([self node:@"a/a2.log"]);
  XCTAssertNil([self node:@"b"]);
  XCTAssertNotNil([self node:@"a/a1.txt"]);
  XCTAssertEqual((unsigned long long)(3000 + 2000 + 12000), [[_controller root] aggregateSize]);

  // The scan root itself cannot be excluded.
  [self selectInTree:@[[_controller root]]];
  XCTAssertFalse([_controller validateAction:@selector(excludeItem:)]);

  NSUInteger index = [[self extensionKeys] indexOfObject:[self key:@"x.txt"]];
  XCTAssertTrue(index != NSNotFound);
  [self selectRow:(NSInteger)index inList:[_controller extensionTable]];
  XCTAssertTrue([_controller validateAction:@selector(excludeExtension:)]);
  // Refresh All: wait for the new scan, not just for idle (the rescan may
  // not have started yet).
  LDUITestController *controller = _controller;
  NSUInteger before = [controller scansFinished];
  [_controller excludeExtension:nil];
  if (![self waitFor:^BOOL { return [controller scansFinished] > before && ![controller isBusy]; } seconds:20.0]) {
    XCTFail(@"the rescan finished");
    return;
  }
  XCTAssertEqualObjects(@"a2.log\n?*.txt", [preferences excludedFilePatterns]);
  XCTAssertNil([self node:@"a/a1.txt"]);
  XCTAssertNil([self node:@"a/sub/deep.txt"]);
  XCTAssertNotNil([self node:@"c.bin"]);
  XCTAssertEqual(NSNotFound, [[self extensionKeys] indexOfObject:[self key:@"x.txt"]]);
}

- (void)testSeveralSelectedItemsShowTheirCounts
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  [self selectInTree:@[[self node:@"a"], [self node:@"c.bin"]]];
  XCTAssertEqualObjects(@"2 Items Selected | 4 Files | 2 Folders", [[_controller statusField] stringValue]);
  [self selectInTree:@[[self node:@"c.bin"]]];
  XCTAssertTrue([[[_controller statusField] stringValue] hasPrefix:[self pathOf:@"c.bin"]]);
}

// The sorted column leaves room for its sort indicator beside the title.
- (void)testSortedColumnFitsItsIndicator
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  NSOutlineView *tree = [_controller tree];
  NSTableColumn *percent = [tree tableColumnWithIdentifier:@"percent"];
  NSTableHeaderCell *header = (NSTableHeaderCell *)[percent headerCell];
  CGFloat title = [header cellSize].width;
  CGFloat indicator = NSWidth([header sortIndicatorRectForBounds:NSMakeRect(0, 0, title, 24)]);
  XCTAssertTrue([percent width] >= title + indicator, @"%g < %g + %g", [percent width], title, indicator);
}

// WinDirStat 2.7: Remove Empty Folders goes bottom-up and keeps folders
// holding files; Change Folder Dates sets each folder to its Last Change.
- (void)testRemoveEmptyFoldersAndChangeFolderDates
{
  if (!_controller) {
    return;
  }
  NSFileManager *files = [NSFileManager defaultManager];
  [files createDirectoryAtPath:[self pathOf:@"e1/e2/e3"] withIntermediateDirectories:YES attributes:nil error:NULL];
  [files createDirectoryAtPath:[self pathOf:@"a/empty"] withIntermediateDirectories:YES attributes:nil error:NULL];
  // A folder holding only one the scan could not read is not empty: its
  // rmdir would fail.
  [files createDirectoryAtPath:[self pathOf:@"u/locked"] withIntermediateDirectories:YES attributes:nil error:NULL];
  chmod([[self pathOf:@"u/locked"] fileSystemRepresentation], 0);
  if (![self scanTree]) {
    chmod([[self pathOf:@"u/locked"] fileSystemRepresentation], 0755);
    return;
  }
  chmod([[self pathOf:@"u/locked"] fileSystemRepresentation], 0755);
  if ([[self node:@"u/locked"] error] != LDFileNodeErrorNone) {
    XCTAssertEqualObjects(@[], [LDCommandRules emptyFoldersIn:@[[self node:@"u"]] rootNode:[_controller root]]);
  }
  [self selectInTree:@[[self node:@"e1"], [self node:@"a"]]];
  XCTAssertTrue([_controller validateAction:@selector(removeEmptyFolders:)]);
  [_controller removeEmptyFolders:nil];
  if (![self waitUntilIdle]) {
    return;
  }
  XCTAssertFalse([files fileExistsAtPath:[self pathOf:@"e1"]]);
  XCTAssertFalse([files fileExistsAtPath:[self pathOf:@"a/empty"]]);
  XCTAssertTrue([files fileExistsAtPath:[self pathOf:@"a/sub/deep.txt"]]);
  XCTAssertNil([self node:@"e1"]);
  XCTAssertNil([self node:@"a/empty"]);
  XCTAssertNotNil([self node:@"a/sub"]);

  LDFileNode *a = [self node:@"a"];
  [self selectInTree:@[a]];
  XCTAssertTrue([_controller validateAction:@selector(setFolderDates:)]);
  NSTimeInterval newest = [a aggregateModificationTime];
  struct timeval old[2] = {{1000000000, 0}, {1000000000, 0}};
  utimes([[self pathOf:@"a"] fileSystemRepresentation], old);
  [_controller setFolderDates:nil];
  if (![self waitUntilIdle]) {
    return;
  }
  struct stat info;
  XCTAssertEqual(0, stat([[self pathOf:@"a"] fileSystemRepresentation], &info));
  XCTAssertEqual((time_t)newest, info.st_mtime);
}

// WinDirStat 2.6: leaving changed filter settings scans again with them.
- (void)testChangedFiltersScanAgain
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setIncludedFolderPatterns:[self pathOf:@"a"]];
  [preferences setExcludedFilePatterns:@"*.log"];
  LDUITestController *controller = _controller;
  NSUInteger before = [controller scansFinished];
  [[NSNotificationCenter defaultCenter] postNotificationName:LDOptionsFiltersDidChangeNotification object:nil];
  XCTAssertTrue([self waitFor:^BOOL { return [controller scansFinished] > before && ![controller isBusy]; } seconds:20.0]);
  XCTAssertNotNil([self node:@"a/a1.txt"]);
  XCTAssertNotNil([self node:@"a/sub/deep.txt"]);
  XCTAssertNil([self node:@"a/a2.log"]);
  XCTAssertNil([self node:@"b"]);
  XCTAssertNil([self node:@"c.bin"]);
}

- (void)testRefreshSelectedUpdatesTotalsAndKeepsExpansionAndSelection
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *a = [self node:@"a"];
  [self revealInTree:[self node:@"a/sub/deep.txt"]];
  [self selectInTree:@[a]];
  unsigned long long before = [[_controller root] aggregateSize];

  [self writeFile:@"a/new.dat" size:7000 seed:7];
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self pathOf:@"a/a2.log"] error:NULL]);
  XCTAssertTrue([_controller validateAction:@selector(refreshSelected:)]);
  [_controller refreshSelected:nil];
  if (![self waitUntilIdle]) {
    return;
  }

  LDFileNode *root = [_controller root];
  LDFileNode *newA = [self node:@"a"];
  XCTAssertNotNil(newA);
  XCTAssertTrue(newA != a);
  XCTAssertEqual(before + 7000 - 5000, [root aggregateSize]);
  XCTAssertEqual((unsigned long long)(3000 + 2000 + 7000), [newA aggregateSize]);
  XCTAssertNil([self node:@"a/a2.log"]);
  XCTAssertNotNil([self node:@"a/new.dat"]);

  // The refreshed folder keeps its place, expansion and selection.
  NSOutlineView *tree = [_controller tree];
  XCTAssertTrue([tree isItemExpanded:root]);
  XCTAssertTrue([tree isItemExpanded:newA]);
  XCTAssertTrue([tree isItemExpanded:[self node:@"a/sub"]], @"expanded folders inside the refreshed one stay expanded");
  XCTAssertEqualObjects(@[newA], [self treeSelection]);
  XCTAssertEqualObjects(@[newA], [_controller selectedNodes]);
  XCTAssertEqual(newA, [[_controller treemap] selectedNode]);

  // Everything derived from the tree follows.
  XCTAssertFalse([[self extensionKeys] containsObject:[self key:@"x.log"]]);
  XCTAssertTrue([[self extensionKeys] containsObject:[self key:@"x.dat"]]);
  XCTAssertEqual(root, [[_controller treemap] rootNode]);
  XCTAssertTrue([[_controller largestFiles] containsObject:[self node:@"a/new.dat"]]);
  XCTAssertTrue([self allInTree:[_controller largestFiles]]);
  XCTAssertTrue([[[_controller statusField] stringValue] hasPrefix:@"5 files, 4 folders"]
                || [[[_controller statusField] stringValue] rangeOfString:@"5 files"].location != NSNotFound,
                @"%@", [[_controller statusField] stringValue]);
}

// Refresh All (and Refresh Selected on the root) scans again: the old tree
// goes, and nothing that showed it keeps it.
- (void)testRefreshAllReplacesTheTree
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *oldRoot = [_controller root];
  [self selectInTree:@[oldRoot]];
  [[_controller fileTabs] selectTabViewItem:[_controller largestTab]];
  [self selectRow:0 inList:[_controller largestTable]];
  [self writeFile:@"b/b2.txt" size:9000 seed:13];
  XCTAssertTrue([_controller validateAction:@selector(rescan:)]);
  LDUITestController *controller = _controller;
  NSUInteger before = [controller scansFinished];
  [_controller rescan:nil];
  XCTAssertTrue([self waitFor:^BOOL { return [controller scansFinished] > before && ![controller isBusy]; } seconds:20.0]);
  for (NSUInteger i = 0; i < 3; i++) {
    [self spin:0.05];
  }
  LDFileNode *root = [_controller root];
  XCTAssertTrue(root != oldRoot);
  XCTAssertEqual(root, [[_controller treemap] rootNode]);
  XCTAssertTrue([[_controller tree] isItemExpanded:root]);
  XCTAssertEqual([_controller tree], (LDOutlineView *)[_controller activeFileList]);
  XCTAssertEqual((NSUInteger)6, [[_controller largestFiles] count]);
  XCTAssertTrue([self allInTree:[_controller largestFiles]]);
  XCTAssertEqual((unsigned long long)(3000 + 5000 + 2000 + 40000 + 9000 + 12000), [root aggregateSize]);
  XCTAssertEqual((NSUInteger)0, [[_controller selectedNodes] count]);
}

- (void)testRefreshOfVolumeUnderThisComputerKeepsFullPaths
{
  if (!_controller || ![self scanPaths:@[[self pathOf:@"a"], [self pathOf:@"b"]]]) {
    return;
  }
  LDFileNode *root = [_controller root];
  XCTAssertTrue([root isComputer]);
  LDFileNode *volume = [self node:@"a"];
  XCTAssertEqual(root, [volume parent]);
  NSTableColumn *name = [[_controller tree] tableColumnWithIdentifier:@"name"];
  XCTAssertEqualObjects([self pathOf:@"a"], [_controller outlineView:[_controller tree] objectValueForTableColumn:name byItem:volume]);

  [self writeFile:@"a/added.txt" size:1000 seed:11];
  [self selectInTree:@[volume]];
  [_controller refreshSelected:nil];
  if (![self waitUntilIdle]) {
    return;
  }

  LDFileNode *refreshed = [self node:@"a"];
  XCTAssertNotNil(refreshed);
  XCTAssertTrue(refreshed != volume);
  XCTAssertEqual(root, [refreshed parent]);
  XCTAssertEqualObjects([self pathOf:@"a"], [refreshed path]);
  XCTAssertEqualObjects([self pathOf:@"a/added.txt"], [[self node:@"a/added.txt"] path]);
  XCTAssertEqualObjects([self pathOf:@"a"], [_controller outlineView:[_controller tree] objectValueForTableColumn:name byItem:refreshed]);
  XCTAssertEqualObjects(@[refreshed], [_controller selectedNodes]);
  XCTAssertEqual((unsigned long long)(3000 + 5000 + 2000 + 1000), [refreshed aggregateSize]);
}

// Linux only: on macOS the trash is the user's.
#if !defined(__APPLE__)
- (void)testMoveToTrashUpdatesEverythingAndUsesThePrivateTrash
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  NSString *dataHome = [[[NSProcessInfo processInfo] environment] objectForKey:@"XDG_DATA_HOME"];
  NSData *trash = [LDFileOperations trashDirectoryForPath:[self pathDataOf:@"c.bin"] error:NULL];
  NSString *trashPath = trash ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:[trash bytes] length:[trash length]] : nil;
  XCTAssertTrue([trashPath hasPrefix:dataHome], @"trash %@ is the private one", trashPath);
  if (![trashPath hasPrefix:dataHome]) {
    return;
  }

  LDFileNode *c = [self node:@"c.bin"];
  unsigned long long before = [[_controller root] aggregateSize];
  [self selectInTree:@[c]];
  XCTAssertTrue([_controller validateAction:@selector(moveToTrash:)]);
  [_controller moveToTrash:nil];
  // Busy until the file operation and the refresh after it are done.
  XCTAssertTrue([_controller isBusy]);
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertFalse([_controller validateAction:@selector(rescan:)]);
  XCTAssertTrue([_controller validateAction:@selector(stopScan:)]);
  if (![self waitUntilIdle]) {
    return;
  }

  NSFileManager *files = [NSFileManager defaultManager];
  XCTAssertFalse([files fileExistsAtPath:[self pathOf:@"c.bin"]]);
  XCTAssertTrue([files fileExistsAtPath:[trashPath stringByAppendingPathComponent:@"files/c.bin"]]);
  XCTAssertTrue([files fileExistsAtPath:[trashPath stringByAppendingPathComponent:@"info/c.bin.trashinfo"]]);
  XCTAssertNil([self node:@"c.bin"]);
  XCTAssertEqual(before - 12000, [[_controller root] aggregateSize]);
  XCTAssertFalse([[self extensionKeys] containsObject:[self key:@"x.bin"]]);
  XCTAssertFalse([[_controller largestFiles] containsObject:c]);
  XCTAssertEqual((NSUInteger)4, [[_controller largestFiles] count]);
  XCTAssertTrue([self allInTree:[_controller largestFiles]]);
  XCTAssertEqual([_controller root], [[_controller treemap] rootNode]);
  XCTAssertTrue([[_controller treemap] selectedNode] != c);
  XCTAssertEqual((NSUInteger)0, [[_controller selectedNodes] count]);
  XCTAssertEqualObjects(@"", [[_controller selectionField] stringValue]);
}
#endif

- (void)testDeletePermanentlyUpdatesTreeListsAndExtensions
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  [_controller showSearchResultsForOptions:[LDSearchOptions optionsWithTerm:@"a1"]];
  XCTAssertEqual((NSUInteger)1, [[_controller searchRows] count]);

  LDFileNode *a = [self node:@"a"];
  unsigned long long before = [[_controller root] aggregateSize];
  [self selectInTree:@[a]];
  XCTAssertTrue([_controller validateAction:@selector(deletePermanently:)]);
  [_controller deletePermanently:nil];
  if (![self waitUntilIdle]) {
    return;
  }

  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[self pathOf:@"a"]]);
  XCTAssertNil([self node:@"a"]);
  XCTAssertEqual(before - 10000, [[_controller root] aggregateSize]);
  XCTAssertEqual((NSUInteger)0, [[_controller searchRows] count]);
  XCTAssertEqualObjects(@"Search Results (0)", [[_controller searchTab] label]);
  XCTAssertFalse([[self extensionKeys] containsObject:[self key:@"x.log"]]);
  XCTAssertTrue([[self extensionKeys] containsObject:[self key:@"x.txt"]]);
  XCTAssertEqual((NSUInteger)2, [[_controller largestFiles] count]);
  XCTAssertTrue([self allInTree:[_controller largestFiles]]);
  XCTAssertEqual((NSInteger)3, [[_controller tree] numberOfRows]);
  XCTAssertEqual([_controller root], [[_controller treemap] rootNode]);
  XCTAssertEqual((NSUInteger)0, [[_controller selectedNodes] count]);
}

// Lists may hold nodes that a refresh detached until they are rebuilt; the
// commands only ever see nodes in the tree.
- (void)testDetachedNodesNeverReachCommands
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  [_controller showSearchResultsForOptions:[LDSearchOptions optionsWithTerm:@"a1"]];
  [self selectRow:0 inList:[_controller searchTable]];
  LDFileNode *a1 = [self node:@"a/a1.txt"];
  XCTAssertEqualObjects(@[a1], [_controller selectedNodes]);

  // The tree is refreshed while the search list still shows a1.
  LDFileNode *a = [self node:@"a"];
  [_controller refreshNodes:@[a]];
  if (![self waitUntilIdle]) {
    return;
  }
  XCTAssertFalse([[_controller root] isAncestorOf:a1]);
  for (LDFileNode *node in [_controller selectedNodes]) {
    XCTAssertTrue([[_controller root] isAncestorOf:node]);
  }
  XCTAssertTrue([self allInTree:[_controller searchRows]]);
  XCTAssertTrue([self allInTree:[_controller largestFiles]]);

  // A file removed behind LinDirStat's back leaves the lists on refresh.
  [_controller showSearchResultsForOptions:[LDSearchOptions optionsWithTerm:@"a1"]];
  [self selectRow:0 inList:[_controller searchTable]];
  XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:[self pathOf:@"a/a1.txt"] error:NULL]);
  [_controller refreshNodes:@[[self node:@"a"]]];
  if (![self waitUntilIdle]) {
    return;
  }
  XCTAssertEqual((NSUInteger)0, [[_controller searchRows] count]);
  XCTAssertEqual((NSUInteger)0, [[_controller selectedNodes] count]);
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertFalse([_controller validateAction:@selector(openItem:)]);
}

#pragma mark - Command enablement

- (void)testCommandEnablementIdleAndBusy
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  [self selectInTree:@[[self node:@"b/b1.txt"]]];
  XCTAssertTrue([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertTrue([_controller validateAction:@selector(deletePermanently:)]);
  XCTAssertTrue([_controller validateAction:@selector(refreshSelected:)]);
  XCTAssertTrue([_controller validateAction:@selector(computeHash:)]);
  XCTAssertFalse([_controller validateAction:@selector(emptyFolder:)]);
  XCTAssertTrue([_controller validateAction:@selector(rescan:)]);
  XCTAssertTrue([_controller validateAction:@selector(search:)]);
  XCTAssertTrue([_controller validateAction:@selector(openPath:)]);
  XCTAssertFalse([_controller validateAction:@selector(stopScan:)]);
  XCTAssertFalse([_controller validateAction:@selector(suspendScan:)]);

  // The root is refreshed but never deleted.
  [self selectInTree:@[[_controller root]]];
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertFalse([_controller validateAction:@selector(moveItemsTo:)]);
  XCTAssertFalse([_controller validateAction:@selector(emptyFolder:)]);
  XCTAssertTrue([_controller validateAction:@selector(refreshSelected:)]);
  XCTAssertTrue([_controller validateAction:@selector(copyPath:)]);

  LDFileNode *b = [self node:@"b"];
  [self selectInTree:@[b]];
  XCTAssertTrue([_controller validateAction:@selector(emptyFolder:)]);
  [_controller refreshSelected:nil];
  XCTAssertTrue([_controller isBusy]);
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertFalse([_controller validateAction:@selector(refreshSelected:)]);
  XCTAssertFalse([_controller validateAction:@selector(emptyFolder:)]);
  XCTAssertFalse([_controller validateAction:@selector(rescan:)]);
  XCTAssertFalse([_controller validateAction:@selector(search:)]);
  XCTAssertFalse([_controller validateAction:@selector(saveResultsToCSV:)]);
  XCTAssertFalse([_controller validateAction:@selector(loadResultsFromCSV:)]);
  XCTAssertFalse([_controller validateAction:@selector(toggleLogicalSize:)]);
  XCTAssertTrue([_controller validateAction:@selector(stopScan:)]);
  // WinDirStat's "early" commands stay.
  XCTAssertTrue([_controller validateAction:@selector(copyPath:)]);
  XCTAssertTrue([_controller validateAction:@selector(openItem:)]);
  if (![self waitUntilIdle]) {
    return;
  }
  XCTAssertTrue([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertTrue([_controller validateAction:@selector(rescan:)]);
  XCTAssertFalse([_controller validateAction:@selector(stopScan:)]);
}

- (void)testCommandEnablementForVolumesAndSpaceItems
{
  if (!_controller || ![self scanPaths:@[[self pathOf:@"a"], [self pathOf:@"b"]]]) {
    return;
  }
  LDFileNode *computer = [_controller root];
  [self selectInTree:@[computer]];
  XCTAssertFalse([_controller validateAction:@selector(openItem:)]);
  XCTAssertFalse([_controller validateAction:@selector(copyPath:)]);
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertTrue([_controller validateAction:@selector(refreshSelected:)]);

  LDFileNode *volume = [self node:@"a"];
  [self selectInTree:@[volume]];
  XCTAssertTrue([_controller validateAction:@selector(openItem:)]);
  XCTAssertTrue([_controller validateAction:@selector(refreshSelected:)]);
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertFalse([_controller validateAction:@selector(deletePermanently:)]);
  XCTAssertFalse([_controller validateAction:@selector(emptyFolder:)]);
  [self selectInTree:@[[self node:@"a/sub"]]];
  XCTAssertTrue([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertTrue([_controller validateAction:@selector(emptyFolder:)]);

  [_controller toggleFreeSpace:nil];
  [_controller toggleUnknown:nil];
  volume = [self node:@"a"];
  LDFileNode *freeSpace = [LDSpaceItems spaceItemOfKind:LDFileNodeKindFreeSpace inVolume:volume];
  LDFileNode *unknown = [LDSpaceItems spaceItemOfKind:LDFileNodeKindUnknown inVolume:volume];
  XCTAssertNotNil(freeSpace);
  for (LDFileNode *item in @[freeSpace ?: volume, unknown ?: volume]) {
    if (![item isSpaceItem]) {
      continue;
    }
    [self selectInTree:@[item]];
    XCTAssertEqualObjects(@[item], [_controller selectedNodes]);
    for (NSString *action in @[@"openItem:", @"copyPath:", @"revealItem:", @"refreshSelected:", @"moveToTrash:",
                               @"deletePermanently:", @"emptyFolder:", @"moveItemsTo:", @"computeHash:", @"showProperties:"]) {
      XCTAssertFalse([_controller validateAction:NSSelectorFromString(action)], @"%@ on %@", action, [item displayName]);
    }
  }
  // A pseudo-item in a selection disables the commands for all of it.
  [self selectInTree:@[[self node:@"a/a1.txt"], freeSpace]];
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertFalse([_controller validateAction:@selector(copyPath:)]);
}

- (void)testCommandEnablementForHardLinkItems
{
  if (!_controller) {
    return;
  }
  [self writeFile:@"b/linked.dat" size:6000 seed:12];
  XCTAssertEqual(0, link([[self pathOf:@"b/linked.dat"] fileSystemRepresentation], [[self pathOf:@"a/link.dat"] fileSystemRepresentation]));
  if (![self scanTree]) {
    return;
  }
  LDFileNode *container = nil;
  for (LDFileNode *child in [[_controller root] children]) {
    if (LDHardLinkItemTypeOfNode(child) == LDHardLinkItemContainer) {
      container = child;
    }
  }
  XCTAssertNotNil(container);
  if (!container) {
    return;
  }
  NSMutableArray *pseudo = [NSMutableArray arrayWithObject:container];
  for (LDFileNode *cursor = container; [[cursor children] count] > 0;) {
    cursor = [[cursor children] objectAtIndex:0];
    [pseudo addObject:cursor];
  }
  XCTAssertEqual(LDHardLinkItemReference, LDHardLinkItemTypeOfNode([pseudo lastObject]));
  for (LDFileNode *item in pseudo) {
    [self selectInTree:@[item]];
    for (NSString *action in @[@"openItem:", @"copyPath:", @"refreshSelected:", @"moveToTrash:", @"deletePermanently:", @"emptyFolder:"]) {
      XCTAssertFalse([_controller validateAction:NSSelectorFromString(action)], @"%@ on %@", action, [item displayName]);
    }
  }
  // The links themselves are ordinary files.
  LDFileNode *link = [self node:@"a/link.dat"];
  XCTAssertTrue([link isHardLink]);
  [self selectInTree:@[link]];
  XCTAssertTrue([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertTrue([_controller validateAction:@selector(openItem:)]);
}

// /dev holds mount points (devpts, mqueue, shm) on Linux; it is only read.
- (void)testCommandEnablementForMountPoints
{
  if (!_controller) {
    return;
  }
  struct stat dev;
  struct stat pts;
  if (stat("/dev", &dev) != 0 || stat("/dev/pts", &pts) != 0 || dev.st_dev == pts.st_dev) {
    NSLog(@"testCommandEnablementForMountPoints: skipped, /dev/pts is not a mount point");
    return;
  }
  if (![self scanPaths:@[@"/dev"]]) {
    return;
  }
  LDFileNode *mount = [_controller nodeForPathData:[NSData dataWithBytes:"/dev/pts" length:8]];
  XCTAssertTrue([mount isMountPoint]);
  [self selectInTree:@[mount]];
  XCTAssertTrue([_controller validateAction:@selector(openItem:)]);
  XCTAssertTrue([_controller validateAction:@selector(refreshSelected:)]);
  XCTAssertFalse([_controller validateAction:@selector(moveToTrash:)]);
  XCTAssertFalse([_controller validateAction:@selector(deletePermanently:)]);
  XCTAssertFalse([_controller validateAction:@selector(emptyFolder:)]);
  XCTAssertFalse([_controller validateAction:@selector(moveItemsTo:)]);
}

#pragma mark - Options

- (NSControlStateValue)menuStateFor:(SEL)action
{
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""];
  [_controller validateMenuItem:item];
  return [item state];
}

- (void)testFreeSpaceAndUnknownTogglesKeepSelection
{
  if (!_controller || ![self scanPaths:@[[self pathOf:@"a"], [self pathOf:@"b"]]]) {
    return;
  }
  LDFileNode *volume = [self node:@"a"];
  LDFileNode *file = [self node:@"b/b1.txt"];
  [self selectInTree:@[file]];
  unsigned long long before = [volume aggregateAllocatedSize];
  XCTAssertEqual(NSOffState, [self menuStateFor:@selector(toggleFreeSpace:)]);

  [_controller toggleFreeSpace:nil];
  XCTAssertEqual(NSOnState, [self menuStateFor:@selector(toggleFreeSpace:)]);
  LDFileNode *freeSpace = [LDSpaceItems spaceItemOfKind:LDFileNodeKindFreeSpace inVolume:volume];
  XCTAssertNotNil(freeSpace);
  XCTAssertNotNil([LDSpaceItems spaceItemOfKind:LDFileNodeKindFreeSpace inVolume:[self node:@"b"]]);
  XCTAssertEqual(before + [freeSpace allocatedSize], [volume aggregateAllocatedSize]);
  [[_controller tree] expandItem:volume];
  XCTAssertTrue([[_controller tree] rowForItem:freeSpace] >= 0);
  XCTAssertEqualObjects(@[file], [_controller selectedNodes]);

  [_controller toggleUnknown:nil];
  XCTAssertEqual(NSOnState, [self menuStateFor:@selector(toggleUnknown:)]);
  XCTAssertNotNil([LDSpaceItems spaceItemOfKind:LDFileNodeKindUnknown inVolume:volume]);
  XCTAssertEqualObjects(@[file], [_controller selectedNodes]);

  [_controller toggleFreeSpace:nil];
  [_controller toggleUnknown:nil];
  XCTAssertNil([LDSpaceItems spaceItemOfKind:LDFileNodeKindFreeSpace inVolume:volume]);
  XCTAssertNil([LDSpaceItems spaceItemOfKind:LDFileNodeKindUnknown inVolume:volume]);
  XCTAssertEqual(before, [volume aggregateAllocatedSize]);
  XCTAssertEqualObjects(@[file], [_controller selectedNodes]);
  XCTAssertEqual(file, [[_controller treemap] selectedNode]);
}

- (void)testFileTypesAndTreemapTogglesKeepSelection
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *deep = [self node:@"a/sub/deep.txt"];
  [self selectInTree:@[deep]];

  XCTAssertEqual(NSOnState, [self menuStateFor:@selector(toggleFileTypes:)]);
  [_controller toggleFileTypes:nil];
  XCTAssertNil([[_controller extensionScroll] superview]);
  XCTAssertEqual(NSOffState, [self menuStateFor:@selector(toggleFileTypes:)]);
  XCTAssertEqualObjects(@[deep], [self treeSelection]);
  [_controller toggleFileTypes:nil];
  XCTAssertEqual([_controller topSplit], [[_controller extensionScroll] superview]);

  [_controller toggleTreemap:nil];
  XCTAssertNil([[_controller treemap] superview]);
  XCTAssertEqual(NSOffState, [self menuStateFor:@selector(toggleTreemap:)]);
  [_controller toggleTreemap:nil];
  XCTAssertEqual([_controller mainSplit], [[_controller treemap] superview]);
  XCTAssertEqualObjects(@[deep], [self treeSelection]);
  XCTAssertTrue([[_controller tree] isItemExpanded:[self node:@"a/sub"]]);
  XCTAssertEqual(deep, [[_controller treemap] selectedNode]);
}

- (void)testColumnVisibilityKeepsSelection
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *a = [self node:@"a"];
  [self selectInTree:@[a]];
  NSOutlineView *tree = [_controller tree];
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setColumn:LDColumnFiles shown:YES];
  NSTableColumn *files = [tree tableColumnWithIdentifier:LDColumnFiles];
  XCTAssertNotNil(files);
  XCTAssertEqualObjects(@"3", [_controller outlineView:tree objectValueForTableColumn:files byItem:a]);
  XCTAssertEqualObjects(@[a], [self treeSelection]);

  [preferences setColumn:LDColumnFiles shown:NO];
  XCTAssertNil([tree tableColumnWithIdentifier:LDColumnFiles]);
  XCTAssertEqualObjects(@[a], [self treeSelection]);
}

- (void)testAbsolutePercentagesToggle
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  NSOutlineView *tree = [_controller tree];
  NSTableColumn *percent = [tree tableColumnWithIdentifier:@"percent"];
  LDFileNode *deep = [self node:@"a/sub/deep.txt"];
  NSString *(^shown)(LDFileNode *) = ^NSString *(LDFileNode *node) {
    return [_controller outlineView:tree objectValueForTableColumn:percent byItem:node];
  };
  NSString *(^formatted)(double) = ^NSString *(double fraction) {
    return [NSString stringWithFormat:@"%.1f%%", fraction * 100.0];
  };
  LDSizeMetric metric = [[LDPreferences sharedPreferences] useLogicalSize] ? LDSizeMetricLogical : LDSizeMetricPhysical;

  // WinDirStat 2.6's default: the share of the whole scan.
  XCTAssertEqual(NSOnState, [self menuStateFor:@selector(toggleAbsolutePercentages:)]);
  XCTAssertEqualObjects(formatted([deep fractionOfRootForMetric:metric]), shown(deep));
  LDFileNode *root = deep;
  while ([root parent]) {
    root = [root parent];
  }
  XCTAssertEqualObjects(@"100.0%", shown(root));
  XCTAssertNotEqualObjects(@"100.0%", shown(deep));

  [_controller toggleAbsolutePercentages:nil];
  XCTAssertFalse([[LDPreferences sharedPreferences] useAbsolutePercentages]);
  XCTAssertEqual(NSOffState, [self menuStateFor:@selector(toggleAbsolutePercentages:)]);
  // deep.txt is the only file in a/sub.
  XCTAssertEqualObjects(@"100.0%", shown(deep));
  XCTAssertEqualObjects(formatted([[deep parent] fractionOfParentForMetric:metric]), shown([deep parent]));
  XCTAssertNotEqualObjects(shown([deep parent]), formatted([[deep parent] fractionOfRootForMetric:metric]));
}

- (void)testUseLogicalSizeResortsAndKeepsSelection
{
  if (!_controller) {
    return;
  }
  NSString *sparse = [self pathOf:@"sparse.img"];
  int fd = open([sparse fileSystemRepresentation], O_CREAT | O_WRONLY, 0644);
  XCTAssertTrue(fd >= 0 && ftruncate(fd, 4 * 1024 * 1024) == 0);
  close(fd);
  if ([self allocatedBytesOnDisk:@"sparse.img"] > 0) {
    NSLog(@"testUseLogicalSizeResortsAndKeepsSelection: skipped, no sparse files here");
    return;
  }
  if (![self scanTree]) {
    return;
  }
  LDFileNode *root = [_controller root];
  NSOutlineView *tree = [_controller tree];
  LDFileNode *c = [self node:@"c.bin"];
  [self selectInTree:@[c]];
  XCTAssertEqual([self node:@"b"], [_controller outlineView:tree child:0 ofItem:root]);
  XCTAssertEqual([self node:@"sparse.img"], [_controller outlineView:tree child:3 ofItem:root]);

  [_controller toggleLogicalSize:nil];
  XCTAssertEqual(NSOnState, [self menuStateFor:@selector(toggleLogicalSize:)]);
  XCTAssertTrue([[LDPreferences sharedPreferences] useLogicalSize]);
  XCTAssertEqual([self node:@"sparse.img"], [_controller outlineView:tree child:0 ofItem:root]);
  XCTAssertEqual([self node:@"b"], [_controller outlineView:tree child:1 ofItem:root]);
  XCTAssertEqualObjects(@[c], [self treeSelection]);
  XCTAssertEqual(c, [[_controller treemap] selectedNode]);
  XCTAssertEqualObjects([@"Logical Size: " stringByAppendingString:[LDSizeFormatter stringForBytes:12000]],
                        [[_controller selectionField] stringValue]);

  [_controller toggleLogicalSize:nil];
  XCTAssertEqual([self node:@"b"], [_controller outlineView:tree child:0 ofItem:root]);
  XCTAssertEqualObjects(@[c], [self treeSelection]);
}

#pragma mark - Preferences keep the view

// Any preference change reloads the display settings; that must not drop
// the tree's selection or expansion.
- (void)testPreferenceChangeKeepsTreeSelectionAndExpansion
{
  if (!_controller || ![self scanTree]) {
    return;
  }
  LDFileNode *b = [self node:@"b"];
  LDFileNode *c = [self node:@"c.bin"];
  LDFileNode *deep = [self node:@"a/sub/deep.txt"];
  [self revealInTree:deep];
  [self selectInTree:@[b, c]];
  LDFileNode *treemapSelection = [[_controller treemap] selectedNode];
  NSString *selectionLabel = [[_controller selectionField] stringValue];

  [[LDPreferences sharedPreferences] setListGrid:YES];

  NSArray *selected = [self treeSelection];
  XCTAssertEqual((NSUInteger)2, [selected count]);
  XCTAssertTrue([selected containsObject:b] && [selected containsObject:c]);
  XCTAssertTrue([[_controller tree] isItemExpanded:[self node:@"a"]]);
  XCTAssertTrue([[_controller tree] isItemExpanded:[self node:@"a/sub"]]);
  XCTAssertEqual(treemapSelection, [[_controller treemap] selectedNode]);
  XCTAssertEqualObjects(selectionLabel, [[_controller selectionField] stringValue]);

  // And the extension list keeps its row and the treemap's highlight.
  NSUInteger index = [[self extensionKeys] indexOfObject:[self key:@"x.txt"]];
  [self selectRow:(NSInteger)index inList:[_controller extensionTable]];
  [[LDPreferences sharedPreferences] setListStripes:YES];
  XCTAssertEqual((NSInteger)index, [[_controller extensionTable] selectedRow]);
  XCTAssertEqualObjects([self key:@"x.txt"], [[_controller treemap] highlightedExtensionKey]);
}

@end
