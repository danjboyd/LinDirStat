#import "AppController.h"
#import "AppController+Private.h"
#import "LDCommandLine.h"
#import "LDCommandRules.h"
#import "LDPreferences.h"
#import "LDFileAttributes.h"
#import "LDDuplicateFinder.h"
#import "LDScanOptions.h"
#import "LDDialogs.h"
#import "LDOptionsWindowController.h"
#import "LDSelectTargetPanel.h"
#import "LDExtensionColor.h"
#import "LDExtensionStats.h"
#import "LDFileNode.h"
#import "LDFileTypeDescriptions.h"
#import "LDFileWatcher.h"
#import "LDHardLinks.h"
#import "LDPlatformUI.h"
#import "LDScanSession.h"
#import "LDSizeFormatter.h"
#import "LDSpaceItems.h"
#import "LDSystemInfo.h"
#import "LDTreeCells.h"
#import "LDTreemapLayout.h"
#import "LDTreemapView.h"
#if defined(GNUSTEP)
#import "GSOpenSave.h"
#endif

#include <sys/stat.h>

static NSString *const LDToolbarSelectTarget = @"SelectTarget";
static NSString *const LDToolbarRefresh = @"Refresh";
static NSString *const LDToolbarStop = @"Stop";
static NSString *const LDToolbarSuspend = @"Suspend";
static NSString *const LDToolbarSearch = @"Search";
static NSString *const LDToolbarTrash = @"Trash";
static NSString *const LDToolbarSelectParent = @"SelectParent";
static NSString *const LDToolbarZoomIn = @"ZoomIn";
static NSString *const LDToolbarZoomOut = @"ZoomOut";

static const CGFloat LDStatusBarHeight = 30.0;
static const NSTimeInterval LDPacmanFrameInterval = 1.0 / 25.0;
static const NSTimeInterval LDLiveReloadInterval = 0.5;

@interface AppController (TableData) <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarDelegate, NSSplitViewDelegate, LDTreemapViewDelegate>
@end

@implementation AppController

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
  (void)notification;
  [self buildMainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  (void)notification;

  _sizeMetric = [[LDPreferences sharedPreferences] useLogicalSize] ? LDSizeMetricLogical : LDSizeMetricPhysical;
  _treeSortKey = _sizeMetric == LDSizeMetricLogical ? LDTreeSortKeyLogicalSize : LDTreeSortKeyPhysicalSize;
  _ownerCache = [NSMapTable strongToStrongObjectsMapTable];
  _detachedSubtrees = [[NSMutableArray alloc] init];
  _treeSortAscending = NO;
  _treeSortIsDefault = YES;
  _swatchCache = [[NSMutableDictionary alloc] init];
  _tintedIcons = [[NSMutableDictionary alloc] init];
  _sortedChildrenCache = [NSMapTable strongToStrongObjectsMapTable];
  _pacmanEpoch = [NSDate timeIntervalSinceReferenceDate];
  _dateFormatter = [[NSDateFormatter alloc] init];
  [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
#if defined(GNUSTEP)
  GSOpenSaveSetMode(GSOpenSaveModeAuto);
#endif

  NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 1280, 820)
                                        styleMask:style
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setTitle:@"LinDirStat"];
  [_window setMinSize:NSMakeSize(720, 480)];
  [_window setFrameAutosaveName:@"LinDirStatMainWindow"];

  [self buildToolbar];
  [self buildWindowContents];
  [self applyDisplayPreferences];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(systemColorsDidChange:)
                                               name:NSSystemColorsDidChangeNotification
                                             object:nil];

  [_window makeKeyAndOrderFront:nil];
  [self applyDefaultSplitPositions];
  [self fitFlexibleColumns];
  [_window makeFirstResponder:_directoryTable];

  _memoryTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(updateMemoryField:)
                                                userInfo:nil
                                                 repeats:YES];
  [self updateMemoryField:nil];
  LDCommandLine *commandLine = [LDCommandLine processCommandLine];
  if ([commandLine loadFromCSVPath]) {
    [self loadResultsFromCSVFile:[commandLine loadFromCSVPath]];
  } else {
    [self beginScanPaths:[self initialScanPaths:commandLine]];
  }
}

// GNUstep also hands the command line's folders to the delegate as files to
// open while launching; LDCommandLine has already taken them. Folders opened
// later (from the desktop) are scanned.
- (void)application:(NSApplication *)application openFiles:(NSArray *)files
{
  if (_window && ![self isBusy]) {
    NSArray *arguments = [@[@"LinDirStat"] arrayByAddingObjectsFromArray:files];
    NSString *currentDirectory = [[NSFileManager defaultManager] currentDirectoryPath];
    NSArray *folders = [[LDCommandLine commandLineWithArguments:arguments currentDirectory:currentDirectory] scanPaths];
    [self beginScanPaths:folders];
  }
  [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

#pragma mark - Menus

- (NSMenuItem *)addItemTo:(NSMenu *)menu title:(NSString *)title action:(SEL)action key:(NSString *)key target:(id)target
{
  NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:title action:action keyEquivalent:key ? key : @""];
  [item setTarget:target];
  return item;
}

- (NSMenu *)addSubmenuTitled:(NSString *)title to:(NSMenu *)mainMenu
{
  NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
  [[mainMenu addItemWithTitle:title action:NULL keyEquivalent:@""] setSubmenu:menu];
  return menu;
}

- (NSString *)functionKey:(unichar)key
{
  return [NSString stringWithCharacters:&key length:1];
}

- (void)buildMainMenu
{
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"LinDirStat"];

  NSMenu *appMenu = [self addSubmenuTitled:@"LinDirStat" to:mainMenu];
  [self addItemTo:appMenu title:@"Preferences" action:@selector(showPreferences:) key:@"," target:self];
  [self addItemTo:appMenu title:@"About LinDirStat" action:@selector(orderFrontStandardAboutPanel:) key:nil target:NSApp];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:appMenu title:@"Quit" action:@selector(terminate:) key:@"q" target:NSApp];

  NSMenu *fileMenu = [self addSubmenuTitled:@"File" to:mainMenu];
  [self addItemTo:fileMenu title:@"Select Target…" action:@selector(openPath:) key:@"o" target:self];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *loadCSV = (NSMenuItem *)[self addItemTo:fileMenu title:@"Load Results From CSV…" action:@selector(loadResultsFromCSV:) key:@"l" target:self];
  [loadCSV setKeyEquivalentModifierMask:NSControlKeyMask | NSAlternateKeyMask];
  NSMenuItem *saveCSV = (NSMenuItem *)[self addItemTo:fileMenu title:@"Save Results To CSV…" action:@selector(saveResultsToCSV:) key:@"s" target:self];
  [saveCSV setKeyEquivalentModifierMask:NSControlKeyMask | NSAlternateKeyMask];
  [self addItemTo:fileMenu title:@"Save Duplicates To CSV…" action:@selector(saveDuplicatesToCSV:) key:nil target:self];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *refreshAll = (NSMenuItem *)[self addItemTo:fileMenu title:@"Refresh All" action:@selector(rescan:) key:[self functionKey:NSF5FunctionKey] target:self];
  [refreshAll setKeyEquivalentModifierMask:NSShiftKeyMask];
  NSMenuItem *refreshSelected = (NSMenuItem *)[self addItemTo:fileMenu title:@"Refresh Selected" action:@selector(refreshSelected:) key:[self functionKey:NSF5FunctionKey] target:self];
  [refreshSelected setKeyEquivalentModifierMask:0];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:fileMenu title:@"Suspend Scan" action:@selector(suspendScan:) key:nil target:self];
  [self addItemTo:fileMenu title:@"Resume Scan" action:@selector(resumeScan:) key:nil target:self];
  [self addItemTo:fileMenu title:@"Stop Scan" action:@selector(stopScan:) key:@"." target:self];

  NSMenu *editMenu = [self addSubmenuTitled:@"Edit" to:mainMenu];
  [self addItemTo:editMenu title:@"Copy Path" action:@selector(copyPath:) key:@"c" target:self];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:editMenu title:@"Search…" action:@selector(search:) key:@"f" target:self];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:editMenu title:@"Compute Hash" action:@selector(computeHash:) key:@"h" target:self];

  NSMenu *cleanupMenu = [self addSubmenuTitled:@"Clean Up" to:mainMenu];
  [self populateCleanupMenu:cleanupMenu forTreemap:NO];
  _cleanupMenu = cleanupMenu;

  NSMenu *treemapMenu = [self addSubmenuTitled:@"Treemap" to:mainMenu];
  [self addItemTo:treemapMenu title:@"Zoom In" action:@selector(zoomIn:) key:@"+" target:self];
  [self addItemTo:treemapMenu title:@"Zoom Out" action:@selector(zoomOut:) key:@"-" target:self];
  [self addItemTo:treemapMenu title:@"Reset Zoom" action:@selector(resetZoom:) key:@"0" target:self];
  [self addItemTo:treemapMenu title:@"Reselect Child" action:@selector(reselectChild:) key:@"=" target:self];
  [self addItemTo:treemapMenu title:@"Select Parent" action:@selector(selectParent:) key:@"u" target:self];
  [treemapMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:treemapMenu title:@"Use Logical Size" action:@selector(toggleLogicalSize:) key:@"l" target:self];
  [self addItemTo:treemapMenu title:@"Show Grid" action:@selector(toggleGrid:) key:nil target:self];
  [self addItemTo:treemapMenu title:@"SequoiaView Layout" action:@selector(toggleLayoutStyle:) key:nil target:self];

  NSMenu *toolsMenu = [self addSubmenuTitled:@"Tools" to:mainMenu];
  [self addItemTo:toolsMenu title:@"Start File Watcher" action:@selector(toggleFileWatcher:) key:nil target:self];

  NSMenu *optionsMenu = [self addSubmenuTitled:@"Options" to:mainMenu];
  [[self addItemTo:optionsMenu title:@"Show Free Space" action:@selector(toggleFreeSpace:) key:[self functionKey:NSF6FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [[self addItemTo:optionsMenu title:@"Show Unknown" action:@selector(toggleUnknown:) key:[self functionKey:NSF7FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [optionsMenu addItem:[NSMenuItem separatorItem]];
  [[self addItemTo:optionsMenu title:@"Show File Types" action:@selector(toggleFileTypes:) key:[self functionKey:NSF8FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [[self addItemTo:optionsMenu title:@"Show Treemap" action:@selector(toggleTreemap:) key:[self functionKey:NSF9FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [optionsMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:optionsMenu title:@"Preferences" action:@selector(showPreferences:) key:nil target:self];

  [LDPlatformUI completeMainMenu:mainMenu applicationMenu:appMenu preferencesTarget:self];
  [NSApp setMainMenu:mainMenu];
}

// WinDirStat recalculates without rescanning; so does LinDirStat. While a
// scan or refresh runs the setting is applied when it finishes.
- (void)toggleFreeSpace:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSArray *selected = [self selectedNodes];
  [preferences setShowFreeSpace:![preferences showFreeSpace]];
  [self applySpaceItemsSelecting:selected];
}

- (void)toggleUnknown:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSArray *selected = [self selectedNodes];
  [preferences setShowUnknown:![preferences showUnknown]];
  [self applySpaceItemsSelecting:selected];
}

// Changing a preference reloads the display settings, which drops the tree
// selection, so the toggles hand over the selection they started with.
- (void)applySpaceItemsSelecting:(NSArray *)selected
{
  if (_rootNode && ![self isBusy]) {
    [self selectTreeNodes:selected];
    [self updateSpaceItems];
    [self didChangeTree];
    [self showSummaryStatus];
  }
}

// Adds, removes or recomputes <Free Space> and <Unknown> under each volume
// root for the Options menu settings.
- (void)updateSpaceItems
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSArray *removed = [LDSpaceItems updateVolumes:[LDSpaceItems volumeNodesOfRoot:_rootNode]
                                   showFreeSpace:[preferences showFreeSpace]
                                     showUnknown:[preferences showUnknown]
                                           usage:[LDSpaceItems diskUsageQuery]
                                          metric:_sizeMetric];
  [_detachedSubtrees addObjectsFromArray:removed];
}

- (void)toggleFileTypes:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowFileTypes:![preferences showFileTypes]];
}

- (void)toggleTreemap:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowTreemap:![preferences showTreemap]];
}

// Hidden panes leave their split view; showing them again restores
// WinDirStat's proportions.
- (void)applyPaneVisibility
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  BOOL extensionsShown = [[_topSplit subviews] indexOfObjectIdenticalTo:_extensionScroll] != NSNotFound;
  if ([preferences showFileTypes] != extensionsShown) {
    if (extensionsShown) {
      [_extensionScroll removeFromSuperview];
      [_topSplit adjustSubviews];
    } else {
      [_topSplit addSubview:_extensionScroll];
      [_topSplit adjustSubviews];
      [_topSplit setPosition:floor([_topSplit bounds].size.width * 0.6) ofDividerAtIndex:0];
    }
  }
  BOOL treemapShown = [[_mainSplit subviews] indexOfObjectIdenticalTo:_treemapView] != NSNotFound;
  if ([preferences showTreemap] != treemapShown) {
    if (treemapShown) {
      [_treemapView removeFromSuperview];
      [_mainSplit adjustSubviews];
    } else {
      [_mainSplit addSubview:_treemapView];
      [_mainSplit adjustSubviews];
      [_mainSplit setPosition:floor([_mainSplit bounds].size.height * 0.5) ofDividerAtIndex:0];
    }
  }
  [self fitFlexibleColumns];
}

// The Clean Up menu, also used (with the treemap's commands) as the context
// menu of the file lists and the treemap (windirstat.rc).
- (void)populateCleanupMenu:(NSMenu *)menu forTreemap:(BOOL)forTreemap
{
  if (forTreemap) {
    [self addItemTo:menu title:@"Zoom In" action:@selector(zoomIn:) key:nil target:self];
    [self addItemTo:menu title:@"Zoom Out" action:@selector(zoomOut:) key:nil target:self];
    [self addItemTo:menu title:@"Reset Zoom" action:@selector(resetZoom:) key:nil target:self];
    [self addItemTo:menu title:@"Reselect Child" action:@selector(reselectChild:) key:nil target:self];
    [self addItemTo:menu title:@"Select Parent" action:@selector(selectParent:) key:nil target:self];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:menu title:@"Copy Path" action:@selector(copyPath:) key:nil target:self];
    [self addItemTo:menu title:[LDPlatformUI showInFileManagerTitle] action:@selector(revealItem:) key:nil target:self];
    [self addItemTo:menu title:@"Open Terminal Here" action:@selector(openTerminal:) key:nil target:self];
    return;
  }
  BOOL isMainMenu = ([menu supermenu] != nil);
  [self addItemTo:menu title:@"Open" action:@selector(openItem:) key:nil target:self];
  [self addItemTo:menu title:[LDPlatformUI showInFileManagerTitle] action:@selector(revealItem:) key:isMainMenu ? @"e" : nil target:self];
  [self addItemTo:menu title:@"Open Terminal Here" action:@selector(openTerminal:) key:isMainMenu ? @"t" : nil target:self];
  if (!isMainMenu) {
    [self addItemTo:menu title:@"Copy Path" action:@selector(copyPath:) key:nil target:self];
    [self addItemTo:menu title:@"Refresh Selected" action:@selector(refreshSelected:) key:nil target:self];
  }
  [self addItemTo:menu title:@"Properties" action:@selector(showProperties:) key:isMainMenu ? @"i" : nil target:self];
  [menu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:menu title:@"Move to Trash" action:@selector(moveToTrash:) key:nil target:self];
  [self addItemTo:menu title:@"Delete Permanently…" action:@selector(deletePermanently:) key:nil target:self];
  if (isMainMenu) {
    [self addItemTo:menu title:@"Empty Trash…" action:@selector(emptyTrash:) key:nil target:self];
  }
  [self addItemTo:menu title:@"Empty Folder…" action:@selector(emptyFolder:) key:nil target:self];
  [self addItemTo:menu title:@"Move To…" action:@selector(moveItemsTo:) key:isMainMenu ? @"m" : nil target:self];
  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *custom = (NSMenuItem *)[menu addItemWithTitle:@"Custom Cleanup" action:NULL keyEquivalent:@""];
  [custom setSubmenu:[self customCleanupMenu]];
  // WinDirStat's "Windows Explorer Menu" (windirstat.rc): the applications
  // that open the selection. The main menu fills it each time it opens;
  // context menus are built for the selection they appear on.
  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *openWith = (NSMenuItem *)[menu addItemWithTitle:@"Open With" action:NULL keyEquivalent:@""];
  NSMenu *openWithMenu = [[NSMenu alloc] initWithTitle:@"Open With"];
  [openWith setSubmenu:openWithMenu];
  if (isMainMenu) {
    [menu setDelegate:(id<NSMenuDelegate>)self];
  } else {
    [self fillOpenWithMenu:openWithMenu forNodes:[self selectedNodes]];
  }
  if (isMainMenu) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(preferencesDidChange:)
                                                 name:LDPreferencesDidChangeNotification
                                               object:nil];
  }
}

- (void)rebuildCustomCleanupMenus
{
  NSMenuItem *custom = (NSMenuItem *)[_cleanupMenu itemWithTitle:@"Custom Cleanup"];
  [custom setSubmenu:[self customCleanupMenu]];
}

- (void)preferencesDidChange:(NSNotification *)notification
{
  (void)notification;
  [self rebuildCustomCleanupMenus];
  [self applyDisplayPreferences];
}

// The Clean Up menu is about to show: fill Open With for the selection.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (menu != _cleanupMenu) {
    return;
  }
  NSArray *nodes = [self selectedNodes];
  BOOL unchanged = [nodes count] == [_openWithNodes count];
  for (NSUInteger i = 0; unchanged && i < [nodes count]; i++) {
    unchanged = [nodes objectAtIndex:i] == [_openWithNodes objectAtIndex:i];
  }
  if (unchanged) {
    return;
  }
  _openWithNodes = nodes;
  [self fillOpenWithMenu:[[_cleanupMenu itemWithTitle:@"Open With"] submenu] forNodes:nodes];
}

- (NSMenu *)contextMenuForListView:(NSTableView *)view
{
  (void)view;
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
  [self populateCleanupMenu:menu forTreemap:NO];
  return menu;
}

- (void)listViewOpenSelection:(NSTableView *)view
{
  (void)view;
  [self openItem:nil];
}

- (void)listView:(NSTableView *)view deleteSelectionPermanently:(BOOL)permanently
{
  (void)view;
  [self deleteNodes:[self selectedNodes] permanently:permanently];
}

- (BOOL)isScanning
{
  return _scanSession && ![_scanSession isFinished];
}

- (NSTimeInterval)pacmanTime
{
  return [NSDate timeIntervalSinceReferenceDate] - _pacmanEpoch;
}

- (BOOL)isBusy
{
  return [self isScanning] || _refreshQueue != nil || _fileOperationRunning;
}

- (BOOL)validateAction:(SEL)action
{
  NSDictionary *commands = @{
    NSStringFromSelector(@selector(openItem:)): @(LDCommandOpen),
    NSStringFromSelector(@selector(showProperties:)): @(LDCommandProperties),
    NSStringFromSelector(@selector(copyPath:)): @(LDCommandCopyPath),
    NSStringFromSelector(@selector(copy:)): @(LDCommandCopyPath),
    NSStringFromSelector(@selector(revealItem:)): @(LDCommandReveal),
    NSStringFromSelector(@selector(openTerminal:)): @(LDCommandTerminal),
    NSStringFromSelector(@selector(refreshSelected:)): @(LDCommandRefreshSelected),
    NSStringFromSelector(@selector(moveToTrash:)): @(LDCommandMoveToTrash),
    NSStringFromSelector(@selector(deletePermanently:)): @(LDCommandDeletePermanently),
    NSStringFromSelector(@selector(emptyFolder:)): @(LDCommandEmptyFolder),
    NSStringFromSelector(@selector(moveItemsTo:)): @(LDCommandMoveTo),
    NSStringFromSelector(@selector(openWithApplication:)): @(LDCommandOpen),
  };
  NSNumber *command = [commands objectForKey:NSStringFromSelector(action)];
  if (command) {
    return [LDCommandRules isCommand:(LDCommand)[command intValue]
                     enabledForNodes:[self selectedNodes]
                            rootNode:_rootNode
                                busy:[self isBusy]];
  }
  if (action == @selector(zoomIn:)) {
    return [_treemapView canZoomIn];
  }
  if (action == @selector(zoomOut:) || action == @selector(resetZoom:)) {
    return [_treemapView canZoomOut];
  }
  if (action == @selector(selectParent:)) {
    return [_treemapView canSelectParent];
  }
  if (action == @selector(reselectChild:)) {
    return [_treemapView canReselectChild];
  }
  if (action == @selector(stopScan:)) {
    return [self isBusy] || [self isFindingDuplicates];
  }
  if (action == @selector(suspendScan:)) {
    return [self isScanning] && ![_scanSession isSuspended];
  }
  if (action == @selector(resumeScan:)) {
    return [self isScanning] && [_scanSession isSuspended];
  }
  if (action == @selector(computeHash:)) {
    return [LDCommandRules isCommand:LDCommandComputeHash enabledForNodes:[self selectedNodes] rootNode:_rootNode busy:[self isBusy]];
  }
  if (action == @selector(search:) || action == @selector(saveResultsToCSV:)) {
    return _rootNode != nil && ![self isBusy];
  }
  if (action == @selector(saveDuplicatesToCSV:)) {
    return [_duplicateGroups count] > 0 && ![self isBusy];
  }
  if (action == @selector(loadResultsFromCSV:)) {
    return ![self isBusy];
  }
  if (action == @selector(toggleFileWatcher:)) {
    return [self isFileWatcherOn] || (_rootNode != nil && [LDFileWatcher isSupported]);
  }
  if (action == @selector(toggleLogicalSize:) || action == @selector(openPath:) || action == @selector(rescan:)
      || action == @selector(emptyTrash:)) {
    return ![self isBusy];
  }
  return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = [item action];
  if (action == @selector(runCustomCleanup:)) {
    NSArray *cleanups = [[LDPreferences sharedPreferences] customCleanups];
    NSInteger slot = [item tag];
    return slot >= 0 && slot < (NSInteger)[cleanups count]
      && [LDCommandRules isCleanup:[cleanups objectAtIndex:(NSUInteger)slot]
                   enabledForNodes:[self selectedNodes]
                          rootNode:_rootNode
                              busy:[self isBusy]];
  }
  if (action == @selector(toggleFreeSpace:)) {
    [item setState:[[LDPreferences sharedPreferences] showFreeSpace] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleUnknown:)) {
    [item setState:[[LDPreferences sharedPreferences] showUnknown] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleFileTypes:)) {
    [item setState:[[LDPreferences sharedPreferences] showFileTypes] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleTreemap:)) {
    [item setState:[[LDPreferences sharedPreferences] showTreemap] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleFileWatcher:)) {
    [item setTitle:[self isFileWatcherOn] ? @"Stop File Watcher" : @"Start File Watcher"];
  }
  if (action == @selector(toggleLogicalSize:)) {
    [item setState:_sizeMetric == LDSizeMetricLogical ? NSOnState : NSOffState];
  } else if (action == @selector(toggleGrid:)) {
    [item setState:[_treemapView options].grid ? NSOnState : NSOffState];
  } else if (action == @selector(toggleLayoutStyle:)) {
    [item setState:[_treemapView options].style == LDTreemapStyleSequoiaView ? NSOnState : NSOffState];
  }
  return [self validateAction:action];
}

#pragma mark - Toolbar

- (void)buildToolbar
{
  NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"LinDirStatToolbar"];
  [toolbar setDelegate:self];
  [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
  [toolbar setAllowsUserCustomization:NO];
  [_window setToolbar:toolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
  (void)toolbar;
  return @[LDToolbarSelectTarget, LDToolbarRefresh, LDToolbarSuspend, LDToolbarStop,
           NSToolbarFlexibleSpaceItemIdentifier,
           LDToolbarSearch, LDToolbarTrash,
           LDToolbarSelectParent, LDToolbarZoomOut, LDToolbarZoomIn];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
  return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag
{
  (void)toolbar;
  (void)flag;
  NSDictionary *specs = @{
    LDToolbarSelectTarget: @[@"Select Target", @"Scan a folder", @"document-open-symbolic", NSStringFromSelector(@selector(openPath:))],
    LDToolbarRefresh: @[@"Refresh", @"Scan the folder again", @"view-refresh-symbolic", NSStringFromSelector(@selector(rescan:))],
    LDToolbarStop: @[@"Stop", @"Stop scanning", @"process-stop-symbolic", NSStringFromSelector(@selector(stopScan:))],
    LDToolbarSuspend: @[@"Suspend", @"Suspend or resume the scan", @"media-playback-pause-symbolic", NSStringFromSelector(@selector(toggleSuspend:))],
    LDToolbarSearch: @[@"Search", @"Search for files by name", @"system-search-symbolic", NSStringFromSelector(@selector(search:))],
    LDToolbarTrash: @[@"Move to Trash", @"Move the selection to the trash", @"user-trash-symbolic", NSStringFromSelector(@selector(moveToTrash:))],
    LDToolbarSelectParent: @[@"Select Parent", @"Select the parent folder", @"go-up-symbolic", NSStringFromSelector(@selector(selectParent:))],
    LDToolbarZoomOut: @[@"Zoom Out", @"Zoom the treemap out", @"zoom-out-symbolic", NSStringFromSelector(@selector(zoomOut:))],
    LDToolbarZoomIn: @[@"Zoom In", @"Zoom the treemap into the selection", @"zoom-in-symbolic", NSStringFromSelector(@selector(zoomIn:))],
  };
  NSArray *spec = [specs objectForKey:identifier];
  if (!spec) {
    return nil;
  }
  NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
  [item setLabel:[spec objectAtIndex:0]];
  [item setPaletteLabel:[spec objectAtIndex:0]];
  [item setToolTip:[spec objectAtIndex:1]];
  [item setImage:[LDPlatformUI toolbarImageNamed:[spec objectAtIndex:2] label:[spec objectAtIndex:0]]];
  [item setTarget:self];
  [item setAction:NSSelectorFromString([spec objectAtIndex:3])];
  return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
  if ([item action] == @selector(toggleSuspend:)) {
    BOOL suspended = [self isScanning] && [_scanSession isSuspended];
    [item setImage:[LDPlatformUI toolbarImageNamed:suspended ? @"media-playback-start-symbolic" : @"media-playback-pause-symbolic"
                                             label:suspended ? @"Resume" : @"Suspend"]];
    [item setToolTip:suspended ? @"Resume the scan" : @"Suspend the scan"];
    return [self isScanning];
  }
  return [self validateAction:[item action]];
}

#pragma mark - Window

- (NSTableColumn *)addColumn:(NSString *)identifier
                       title:(NSString *)title
                       width:(CGFloat)width
                       right:(BOOL)rightAligned
                     toTable:(NSTableView *)table
{
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
  [[column headerCell] setStringValue:title];
  [column setWidth:width];
  [column setMinWidth:40.0];
  if (!_naturalColumnWidths) {
    _naturalColumnWidths = [NSMapTable strongToStrongObjectsMapTable];
  }
  [_naturalColumnWidths setObject:@(width) forKey:column];
  [column setEditable:NO];
  if (rightAligned) {
    [[column dataCell] setAlignment:NSRightTextAlignment];
    [[column headerCell] setAlignment:NSRightTextAlignment];
  }
  [table addTableColumn:column];
  return column;
}

- (void)setSortPrototypeForColumn:(NSTableColumn *)column ascending:(BOOL)ascending
{
  [column setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:[column identifier] ascending:ascending]];
}

- (NSScrollView *)scrollViewWithDocumentView:(NSView *)view
{
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:YES];
  [scroll setBorderType:NSNoBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [scroll setDocumentView:view];
  // The header's corner is only needed beside a classic scroller; with
  // overlay scrollbars it would hide the last column's title.
  if ([view isKindOfClass:[NSTableView class]]) {
    [(NSTableView *)view setCornerView:nil];
  }
  return scroll;
}

- (NSTextField *)statusLabel
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [[label cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  return label;
}

- (void)buildDirectoryTable
{
  _directoryTable = [[LDOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 700, 300)];
  [_directoryTable setCommandTarget:self];
  NSTableColumn *name = [self addColumn:@"name" title:@"Name" width:220 right:NO toTable:_directoryTable];
  LDIconTextCell *nameCell = [[LDIconTextCell alloc] initTextCell:@""];
  [nameCell setLineBreakMode:NSLineBreakByTruncatingTail];
  [name setDataCell:nameCell];
  [name setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
  [_directoryTable setOutlineTableColumn:name];
  [self setSortPrototypeForColumn:name ascending:YES];

  NSTableColumn *subtree = [self addColumn:@"subtree" title:@"Subtree Percentage" width:130 right:NO toTable:_directoryTable];
  [subtree setDataCell:[[LDPercentageBarCell alloc] init]];
  [self setSortPrototypeForColumn:subtree ascending:NO];
  NSTableColumn *percent = [self addColumn:@"percent" title:@"Percentage" width:90 right:YES toTable:_directoryTable];
  [self setSortPrototypeForColumn:percent ascending:NO];

  // WinDirStat's optional columns, shown per Preferences > Folder List.
  NSDictionary *specs = @{
    LDColumnPhysicalSize: @[@"Physical Size", @90, @YES],
    LDColumnLogicalSize: @[@"Logical Size", @90, @YES],
    LDColumnItems: @[@"Items", @70, @YES],
    LDColumnFiles: @[@"Files", @70, @YES],
    LDColumnFolders: @[@"Folders", @70, @YES],
    LDColumnLastChange: @[@"Last Change", @140, @NO],
    LDColumnAttributes: @[@"Attributes", @80, @NO],
    LDColumnOwner: @[@"Owner", @110, @NO],
  };
  _optionalColumns = [[NSMutableDictionary alloc] init];
  for (NSString *identifier in [LDPreferences optionalColumns]) {
    NSArray *spec = [specs objectForKey:identifier];
    NSTableColumn *column = [self addColumn:identifier
                                      title:[spec objectAtIndex:0]
                                      width:[[spec objectAtIndex:1] doubleValue]
                                      right:[[spec objectAtIndex:2] boolValue]
                                    toTable:_directoryTable];
    if (![identifier isEqualToString:LDColumnAttributes] && ![identifier isEqualToString:LDColumnOwner]) {
      [self setSortPrototypeForColumn:column ascending:[identifier isEqualToString:LDColumnLastChange]];
    }
    [_optionalColumns setObject:column forKey:identifier];
  }

  [name setMinWidth:160.0];
  [_directoryTable setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  [_directoryTable setAllowsMultipleSelection:YES];
  // Header clicks sort; GTK never selects (and tints) a whole column.
  [_directoryTable setAllowsColumnSelection:NO];
  [_directoryTable setAutosaveName:@"LinDirStatDirectoryTree3"];
  [_directoryTable setAutosaveTableColumns:YES];
  [_directoryTable setDataSource:self];
  [_directoryTable setDelegate:self];
  [_directoryTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"percent" ascending:NO]]];
  [self applyColumnVisibility];
}

// WinDirStat's CreateColumns: the optional columns that are on, in their
// fixed order after Percentage.
- (void)applyColumnVisibility
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  BOOL changed = NO;
  for (NSString *identifier in [LDPreferences optionalColumns]) {
    NSTableColumn *column = [_optionalColumns objectForKey:identifier];
    BOOL shown = [preferences isColumnShown:identifier];
    BOOL present = [[_directoryTable tableColumns] indexOfObjectIdenticalTo:column] != NSNotFound;
    if (shown != present) {
      changed = YES;
    }
  }
  if (!changed) {
    return;
  }
  for (NSString *identifier in [LDPreferences optionalColumns]) {
    NSTableColumn *column = [_optionalColumns objectForKey:identifier];
    if ([[_directoryTable tableColumns] indexOfObjectIdenticalTo:column] != NSNotFound) {
      [_directoryTable removeTableColumn:column];
    }
  }
  for (NSString *identifier in [LDPreferences optionalColumns]) {
    if ([preferences isColumnShown:identifier]) {
      [_directoryTable addTableColumn:[_optionalColumns objectForKey:identifier]];
    }
  }
  [self fitFlexibleColumns];
  [_directoryTable reloadData];
}

// Applies settings that change how things look (Preferences window).
- (void)applyDisplayPreferences
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [LDSizeFormatter setHumanReadable:[preferences humanFormat]];
  for (NSTableView *table in @[_directoryTable, _extensionTable]) {
    [table setUsesAlternatingRowBackgroundColors:[preferences listStripes]];
    [table setGridStyleMask:[preferences listGrid] ? (NSTableViewSolidVerticalGridLineMask | NSTableViewSolidHorizontalGridLineMask) : NSTableViewGridNone];
    [table setNeedsDisplay:YES];
  }
  [self applyColumnVisibility];
  if (_mainSplit) {
    [self applyPaneVisibility];
  }

  LDTreemapOptions options = [_treemapView options];
  options.style = [preferences treemapStyle] == 1 ? LDTreemapStyleSequoiaView : LDTreemapStyleKDirStat;
  options.grid = [preferences treemapGrid];
  options.brightness = [preferences treemapBrightness] / 100.0;
  options.ambientLight = [preferences treemapCushionShading] / 100.0;
  options.height = [preferences treemapHeight] / 100.0;
  options.scaleFactor = [preferences treemapScaleFactor] / 100.0;
  options.lightSourceX = [preferences treemapLightSourceX] / 100.0;
  options.lightSourceY = [preferences treemapLightSourceY] / 100.0;
  LDTreemapOptions current = [_treemapView options];
  if (memcmp(&options, &current, sizeof(options)) != 0) {
    [_treemapView setOptions:options];
    [_swatchCache removeAllObjects];
    [_extensionTable setNeedsDisplay:YES];
  }
  [_directoryTable reloadData];
  [_extensionTable reloadData];
  [self updateSelectionField];
}

- (void)showPreferences:(id)sender
{
  (void)sender;
  [[LDOptionsWindowController sharedController] showWindow:nil];
}

- (void)buildExtensionTable
{
  _extensionTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 360, 300)];
  // WinDirStat's columns; only the description gives or takes width.
  NSTableColumn *extension = [self addColumn:@"extension" title:@"Extension" width:84 right:NO toTable:_extensionTable];
  [[extension dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [self setSortPrototypeForColumn:extension ascending:YES];
  NSTableColumn *color = [self addColumn:@"color" title:@"Color" width:50 right:NO toTable:_extensionTable];
  [color setDataCell:[[NSImageCell alloc] initImageCell:nil]];
  NSTableColumn *description = [self addColumn:@"description" title:@"Description" width:120 right:NO toTable:_extensionTable];
  [[description dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [self setSortPrototypeForColumn:description ascending:YES];
  NSTableColumn *bytes = [self addColumn:@"bytes" title:@"Bytes" width:80 right:YES toTable:_extensionTable];
  [self setSortPrototypeForColumn:bytes ascending:NO];
  NSTableColumn *percent = [self addColumn:@"percent" title:@"% Bytes" width:80 right:YES toTable:_extensionTable];
  [self setSortPrototypeForColumn:percent ascending:NO];
  NSTableColumn *files = [self addColumn:@"files" title:@"Files" width:72 right:YES toTable:_extensionTable];
  [self setSortPrototypeForColumn:files ascending:NO];
  // GNUstep's autoresizing styles shrink every column; the description is
  // fitted by hand instead (-fitExtensionDescriptionColumn).
  [description setMinWidth:60.0];
  [_extensionTable setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];

  [_extensionTable setAllowsMultipleSelection:NO];
  [_extensionTable setAllowsColumnSelection:NO];
  [_extensionTable setAutosaveName:@"LinDirStatExtensionList3"];
  [_extensionTable setAutosaveTableColumns:YES];
  [_extensionTable setDataSource:self];
  [_extensionTable setDelegate:self];
  [_extensionTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"bytes" ascending:NO]]];
}

- (void)buildStatusBarInView:(NSView *)content
{
  NSRect bounds = [content bounds];
  NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, LDStatusBarHeight, bounds.size.width, 1)];
  [separator setBoxType:NSBoxSeparator];
  [separator setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [content addSubview:separator];

  _spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12, 7, 16, 16)];
  [_spinner setStyle:NSProgressIndicatorSpinningStyle];
  [_spinner setDisplayedWhenStopped:NO];
  [_spinner setIndeterminate:YES];
  [_spinner setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
  [content addSubview:_spinner];

  CGFloat memoryWidth = 130.0;
  CGFloat selectionWidth = 190.0;
  _memoryField = [self statusLabel];
  [_memoryField setAlignment:NSRightTextAlignment];
  [_memoryField setFrame:NSMakeRect(bounds.size.width - memoryWidth - 12, 6, memoryWidth, 18)];
  [_memoryField setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:_memoryField];

  _selectionField = [self statusLabel];
  [_selectionField setAlignment:NSRightTextAlignment];
  [_selectionField setFrame:NSMakeRect(NSMinX([_memoryField frame]) - selectionWidth - 12, 6, selectionWidth, 18)];
  [_selectionField setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:_selectionField];

  _statusField = [self statusLabel];
  [_statusField setStringValue:@"Ready"];
  [_statusField setFrame:NSMakeRect(36, 6, NSMinX([_selectionField frame]) - 48, 18)];
  [_statusField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [content addSubview:_statusField];
}

- (void)buildWindowContents
{
  NSView *content = [_window contentView];
  NSRect bounds = [content bounds];
  [self buildStatusBarInView:content];
  [self buildDirectoryTable];
  [self buildExtensionTable];

  _treemapView = [[LDTreemapView alloc] initWithFrame:NSMakeRect(0, 0, bounds.size.width, 300)];
  [_treemapView setDelegate:self];
  NSMenu *treemapMenu = [[NSMenu alloc] initWithTitle:@""];
  [self populateCleanupMenu:treemapMenu forTreemap:YES];
  [_treemapView setMenu:treemapMenu];
  [_treemapView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  // WinDirStat's composition: directory tree and extension list side by
  // side above the full-width treemap.
  _topSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, bounds.size.width, 300)];
  [_topSplit setVertical:YES];
  [_topSplit setDividerStyle:NSSplitViewDividerStyleThin];
  [_topSplit setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [_topSplit addSubview:[self buildFileTabs]];
  _extensionScroll = [self scrollViewWithDocumentView:_extensionTable];
  [_topSplit addSubview:_extensionScroll];
  [_topSplit setDelegate:self];

  NSRect splitFrame = NSMakeRect(0, LDStatusBarHeight + 1, bounds.size.width, bounds.size.height - LDStatusBarHeight - 1);
  _mainSplit = [[NSSplitView alloc] initWithFrame:splitFrame];
  [_mainSplit setVertical:NO];
  [_mainSplit setDividerStyle:NSSplitViewDividerStyleThin];
  [_mainSplit setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [_mainSplit addSubview:_topSplit];
  [_mainSplit addSubview:_treemapView];
  [_mainSplit setDelegate:self];
  [content addSubview:_mainSplit];
}

// The treemap takes half the height, as in WinDirStat; the extension list
// takes 40% of the width (WinDirStat: 28%) so its description fits at
// GNOME's metrics.
// Saved positions win once the user drags.
- (void)applyDefaultSplitPositions
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  BOOL mainSaved = [defaults objectForKey:@"NSSplitView Subview Frames LinDirStatMainSplit"] != nil;
  BOOL topSaved = [defaults objectForKey:@"NSSplitView Subview Frames LinDirStatTopSplit"] != nil;
  [_mainSplit setAutosaveName:@"LinDirStatMainSplit"];
  [_topSplit setAutosaveName:@"LinDirStatTopSplit"];
  if (!mainSaved) {
    [_mainSplit setPosition:floor([_mainSplit bounds].size.height * 0.5) ofDividerAtIndex:0];
  }
  if (!topSaved) {
    [_topSplit setPosition:floor([_topSplit bounds].size.width * 0.6) ofDividerAtIndex:0];
  }
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
  (void)index;
  return MAX(proposed, splitView == _mainSplit ? 120.0 : 240.0);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
  (void)index;
  CGFloat extent = splitView == _mainSplit ? [splitView bounds].size.height : [splitView bounds].size.width;
  return MIN(proposed, extent - (splitView == _mainSplit ? 120.0 : 200.0));
}

// Gives one column whatever width its table's pane has left, as GTK's
// expanding columns do. GNUstep's autoresizing styles resize every column and
// are not applied until the table resizes, so this is done by hand.
- (void)fitColumn:(NSString *)identifier ofTable:(NSTableView *)table
{
  NSTableColumn *flexible = [table tableColumnWithIdentifier:identifier];
  if ([LDPlatformUI tablesAutoresizeColumns]) {
    // Only the flexible column takes up (or gives back) the pane's width.
    if ([table columnAutoresizingStyle] != NSTableViewUniformColumnAutoresizingStyle) {
      for (NSTableColumn *column in [table tableColumns]) {
        [column setResizingMask:column == flexible ? (NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask)
                                                   : NSTableColumnUserResizingMask];
      }
      // A narrow pane scrolls sideways rather than squeezing the name away.
      [flexible setMinWidth:MAX([flexible minWidth], 140.0)];
      [table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
      [table setFocusRingType:NSFocusRingTypeNone];
      [table sizeToFit];
    }
    return;
  }
  // GNUstep also resizes the last column whenever the pane or its scroller
  // changes (-setColumnAutoresizingStyle: is not implemented), which would
  // starve the flexible column or the last one; the last column keeps its
  // natural width.
  NSTableColumn *last = [[table tableColumns] lastObject];
  NSNumber *natural = [_naturalColumnWidths objectForKey:last];
  if (last != flexible && natural && [last width] != [natural doubleValue]) {
    [last setWidth:[natural doubleValue]];
  }
  CGFloat spacing = [table intercellSpacing].width;
  CGFloat available = [[table enclosingScrollView] contentSize].width;
  CGFloat others = 0.0;
  for (NSTableColumn *column in [table tableColumns]) {
    if (column != flexible) {
      others += [column width] + spacing;
    }
  }
  [flexible setWidth:MAX([flexible minWidth], floor(available - others - spacing))];
}

- (void)fitFlexibleColumns
{
  [self fitColumn:@"name" ofTable:_directoryTable];
  if (_fileTabs) {
    for (NSTableView *list in @[_largestTable, _searchTable, _duplicatesTable, _watcherTable]) {
      [self fitColumn:@"path" ofTable:list];
    }
  }
  [self fitColumn:@"description" ofTable:_extensionTable];
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
  (void)notification;
  [self fitFlexibleColumns];
}

- (void)systemColorsDidChange:(NSNotification *)notification
{
  (void)notification;
  [_tintedIcons removeAllObjects];
  [_directoryTable setNeedsDisplay:YES];
}

- (void)updateMemoryField:(NSTimer *)timer
{
  (void)timer;
  unsigned long long bytes = LDResidentMemoryBytes();
  [_memoryField setStringValue:bytes ? [NSString stringWithFormat:@"Memory: %@", [LDSizeFormatter stringForBytes:bytes]] : @""];
}

#pragma mark - Scanning

- (NSString *)defaultFixturePath
{
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *fixture = [cwd stringByAppendingPathComponent:@"Tests/Fixtures/basic-tree"];
  if ([[NSFileManager defaultManager] fileExistsAtPath:fixture]) {
    return fixture;
  }
  return NSHomeDirectory();
}

- (NSArray *)initialScanPaths:(LDCommandLine *)commandLine
{
  if ([[commandLine scanPaths] count] > 0) {
    return [commandLine scanPaths];
  }
  NSString *environmentPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"LINDIRSTAT_SCAN_PATH"];
  if ([environmentPath length] > 0) {
    return @[environmentPath];
  }
  return @[[self defaultFixturePath]];
}

- (NSString *)displayPath:(NSString *)path
{
  return [path stringByAbbreviatingWithTildeInPath];
}

- (void)refreshCommandState
{
  [[_window toolbar] validateVisibleItems];
}

- (void)beginScanPath:(NSString *)scanPath
{
  if (scanPath) {
    [self beginScanPaths:@[scanPath]];
  }
}

// One path scans that folder; several (volumes from Select Target) scan
// under a "This Computer" root.
- (void)beginScanPaths:(NSArray *)scanPaths
{
  if ([scanPaths count] == 0 || ![self scanOptionsAreValid]) {
    return;
  }
  NSString *scanPath = [scanPaths objectAtIndex:0];
  _currentScanPaths = [scanPaths copy];

  [_refreshSession cancel];
  _refreshSession = nil;
  _refreshQueue = nil;
  _currentScanPath = [scanPath copy];
  _loadedFile = nil;
  [self clearResults];
  [self resetFileListsForScan];
  [_detachedSubtrees removeAllObjects];

  LDScanSession *session = [[LDScanSession alloc] init];
  _scanSession = session;
  [self configureScanSession:session];
  [session startAsyncScanPaths:scanPaths completion:^{
    // Ignore a scan that was replaced before it finished.
    if (session == _scanSession) {
      [self finishAsyncScan];
    }
  }];
  [self fileListsDidStartScan];

  [_window setTitle:[scanPaths count] > 1 ? @"This Computer" : [self displayPath:scanPath]];
  _lastLiveReload = 0.0;
  [self startBusyIndicator];
  [self updateScanStatus];
  [self refreshCommandState];
}

- (void)configureScanSession:(LDScanSession *)session
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [session setSortMetric:_sizeMetric];
  [session setScanOptions:[LDScanOptions optionsFromPreferences:preferences]];
}

// Filters with a bad pattern are reported before scanning, as WinDirStat
// reports "Invalid filter" when they are entered.
- (BOOL)scanOptionsAreValid
{
  NSError *error = nil;
  if ([[LDScanOptions optionsFromPreferences:[LDPreferences sharedPreferences]] validateWithError:&error]) {
    return YES;
  }
  [LDDialogs showFailures:@[[error localizedDescription] ?: @"Invalid filter"]
                    title:@"Fix the filter in Preferences › Filtering before scanning"];
  return NO;
}

// The timer animates the pacmen while anything runs. While scanning, it
// also re-sorts and reloads the growing tree a few times a second;
// completion arrives through the session's completion block.
- (void)startBusyIndicator
{
  [_spinner startAnimation:nil];
  if (!_busyTimer) {
    _busyTimer = [NSTimer scheduledTimerWithTimeInterval:LDPacmanFrameInterval
                                                  target:self
                                                selector:@selector(busyTimerFired:)
                                                userInfo:nil
                                                 repeats:YES];
  }
}

- (void)finishBusyWork
{
  if ([self isBusy]) {
    return;
  }
  [_busyTimer invalidate];
  _busyTimer = nil;
  [_spinner stopAnimation:nil];
  [self refreshCommandState];
  [self showSummaryStatus];
  [_directoryTable setNeedsDisplay:YES];
}

- (void)showStatus:(NSString *)status
{
  [_statusField setStringValue:status ?: @""];
}

// Forgets the previous results before a new scan.
- (void)clearResults
{
  if (_rootNode) {
    // The outline view keeps expanded items alive until they are collapsed.
    [_directoryTable collapseItem:_rootNode collapseChildren:YES];
  }
  _rootNode = nil;
  _extensionRows = @[];
  [_sortedChildrenCache removeAllObjects];
  [_treemapView setRootNode:nil metric:_sizeMetric colorIndexes:nil];
  _syncingSelection = YES;
  [_directoryTable reloadData];
  [_extensionTable reloadData];
  _syncingSelection = NO;
  [self updateSelectionField];
}

- (void)updateScanStatus
{
  if ([_scanSession isCanceled]) {
    [_statusField setStringValue:@"Stopping…"];
    return;
  }
  NSString *currentPath = [_scanSession currentPath];
  [_statusField setStringValue:[NSString stringWithFormat:@"Scanning %@  ·  %lu files, %lu folders, %@",
                                [self displayPath:currentPath ? currentPath : _currentScanPath],
                                (unsigned long)[_scanSession filesScanned],
                                (unsigned long)[_scanSession directoriesScanned],
                                [LDSizeFormatter stringForBytes:[_scanSession bytesScanned]]]];
}

- (void)busyTimerFired:(NSTimer *)timer
{
  (void)timer;
  if (![self isScanning]) {
    [self redrawSubtreeColumn];
    return;
  }
  NSTimeInterval elapsed = [_scanSession elapsedTime];
  if (!_rootNode && [_scanSession rootNode]) {
    _rootNode = [_scanSession rootNode];
    [_directoryTable reloadData];
    [_directoryTable expandItem:_rootNode];
  }
  if (elapsed - _lastLiveReload >= LDLiveReloadInterval) {
    _lastLiveReload = elapsed;
    [self updateScanStatus];
    [self reloadTreeKeepingSelection];
    if ([self activeFileList] == _largestTable) {
      [self updateLargestFiles];
    }
  } else {
    [self redrawSubtreeColumn];
  }
}

// Re-sorts the visible tree for the latest sizes.
- (void)reloadTreeKeepingSelection
{
  NSInteger row = [_directoryTable selectedRow];
  id selected = row >= 0 ? [_directoryTable itemAtRow:row] : nil;
  [_sortedChildrenCache removeAllObjects];
  _syncingSelection = YES;
  [_directoryTable reloadData];
  NSInteger newRow = selected ? [_directoryTable rowForItem:selected] : -1;
  if (newRow >= 0) {
    [_directoryTable selectRow:newRow byExtendingSelection:NO];
  } else {
    [_directoryTable deselectAll:nil];
  }
  _syncingSelection = NO;
}

- (void)redrawSubtreeColumn
{
  NSInteger column = [_directoryTable columnWithIdentifier:@"subtree"];
  if (column >= 0) {
    [_directoryTable setNeedsDisplayInRect:NSIntersectionRect([_directoryTable rectOfColumn:column],
                                                              [_directoryTable visibleRect])];
  }
}

- (void)finishAsyncScan
{
  LDFileNode *root = [_scanSession rootNode];
  [self finishBusyWork];
  if (!root) {
    [_statusField setStringValue:@"Scan failed"];
    return;
  }

  BOOL sameRoot = (root == _rootNode);
  _rootNode = root;
  [self updateSpaceItems];
  [self reloadResults];
  if (!sameRoot) {
    [_directoryTable expandItem:root];
  }
  [self showSummaryStatus];
  [self updateSelectionField];
  [self fileListsDidFinishScan];
  if (!_loadedFile) {
    [LDPlatformUI scanDidFinishWithRoot:root window:_window];
  }
}

- (void)showSummaryStatus
{
  if (!_rootNode) {
    [_statusField setStringValue:@"Ready"];
    return;
  }
  NSString *canceled = [_scanSession state] == LDScanSessionStateCanceled ? @"Scan stopped, partial results  ·  " : @"";
  NSString *problems = @"";
  if ([_scanSession errorCount] > 0) {
    problems = [NSString stringWithFormat:@", %lu unreadable", (unsigned long)[_scanSession errorCount]];
  }
  if (_loadedFile) {
    [_statusField setStringValue:[NSString stringWithFormat:@"%lu files, %lu folders, %@  ·  loaded from %@",
                                  (unsigned long)[_rootNode fileCount],
                                  (unsigned long)MAX((NSUInteger)1, [_rootNode directoryCount]) - 1,
                                  [LDSizeFormatter stringForBytes:[_rootNode aggregateSizeForMetric:_sizeMetric]],
                                  [self displayPath:_loadedFile]]];
    return;
  }
  [_statusField setStringValue:[NSString stringWithFormat:@"%@%lu files, %lu folders, %@%@ in %.1f s",
                                canceled,
                                (unsigned long)[_rootNode fileCount],
                                (unsigned long)MAX((NSUInteger)1, [_rootNode directoryCount]) - 1,
                                [LDSizeFormatter stringForBytes:[_rootNode aggregateSizeForMetric:_sizeMetric]],
                                problems,
                                [_scanSession elapsedTime]]];
}

// Rebuilds the extension list and treemap from _rootNode for the current metric.
- (void)reloadResults
{
  [_sortedChildrenCache removeAllObjects];
  [_ownerCache removeAllObjects];
  _extensionRows = [self sortedExtensionRows:[LDExtensionStats sortedStatsForRootNode:_rootNode metric:_sizeMetric]];
  _syncingSelection = YES;
  [_directoryTable deselectAll:nil];
  [_extensionTable deselectAll:nil];
  _syncingSelection = NO;
  [_treemapView setHighlightedExtensionKey:nil];
  [_treemapView setRootNode:_rootNode
                     metric:_sizeMetric
               colorIndexes:[LDExtensionStats colorIndexMapForSortedStats:_extensionRows]];
  [_directoryTable reloadData];
  [_extensionTable reloadData];
  [self fitFlexibleColumns];
}

// After refreshes and deletions: rebuild what is derived from the tree,
// keeping the selection and zoom where the nodes still exist.
- (void)didChangeTree
{
  NSArray *selected = [self selectedNodes];
  LDFileNode *zoom = [_treemapView zoomNode];
  LDFileNode *treemapSelection = [_treemapView selectedNode];
  [self reloadResults];
  if (zoom && [_rootNode isAncestorOf:zoom]) {
    [_treemapView setZoomNode:zoom];
  }
  [self selectTreeNodes:selected];
  if (treemapSelection && [_rootNode isAncestorOf:treemapSelection]) {
    [_treemapView setSelectedNode:treemapSelection];
  }
  [self fileListsDidChangeTree];
  [self updateSelectionField];
  [self refreshCommandState];
}

// Selects the rows of those nodes that are still in the tree.
- (void)selectTreeNodes:(NSArray *)nodes
{
  _syncingSelection = YES;
  NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
  for (LDFileNode *node in nodes) {
    NSInteger row = [_rootNode isAncestorOf:node] ? [_directoryTable rowForItem:node] : -1;
    if (row >= 0) {
      [rows addIndex:(NSUInteger)row];
    }
  }
  [_directoryTable selectRowIndexes:rows byExtendingSelection:NO];
  _syncingSelection = NO;
}

- (void)forgetNode:(LDFileNode *)node replacement:(LDFileNode *)replacement
{
  BOOL wasExpanded = [_directoryTable isItemExpanded:node];
  BOOL wasSelected = [[self selectedNodes] indexOfObjectIdenticalTo:node] != NSNotFound;
  [_directoryTable collapseItem:node collapseChildren:YES];
  [_sortedChildrenCache removeAllObjects];
  [_directoryTable reloadData];
  if (replacement && wasExpanded) {
    [_directoryTable expandItem:replacement];
  }
  if (replacement && wasSelected) {
    NSInteger row = [_directoryTable rowForItem:replacement];
    if (row >= 0) {
      _syncingSelection = YES;
      [_directoryTable selectRow:row byExtendingSelection:YES];
      _syncingSelection = NO;
    }
    [_treemapView setSelectedNode:replacement];
  }
}

- (void)showLoadedTree:(LDFileNode *)root fromFile:(NSString *)path
{
  [_scanSession cancel];
  _scanSession = nil;
  [self clearResults];
  [self resetFileListsForScan];
  [_detachedSubtrees removeAllObjects];
  _loadedFile = [path copy];
  _currentScanPath = [[root path] copy];
  _currentScanPaths = [root isComputer] ? nil : @[_currentScanPath];
  if (_sizeMetric != LDSizeMetricPhysical) {
    [root sortChildrenByMetric:_sizeMetric];
  }
  _rootNode = root;
  [self reloadResults];
  [_directoryTable expandItem:root];
  [_window setTitle:[NSString stringWithFormat:@"%@ (%@)", [self displayPath:[root path]], [path lastPathComponent]]];
  [self showSummaryStatus];
  [self refreshCommandState];
  [self fileListsDidFinishScan];
}

- (void)suspendScan:(id)sender
{
  (void)sender;
  [_scanSession suspend];
  [self showStatus:@"Scan suspended"];
  [self refreshCommandState];
}

- (void)toggleSuspend:(id)sender
{
  if ([_scanSession isSuspended]) {
    [self resumeScan:sender];
  } else {
    [self suspendScan:sender];
  }
}

- (void)resumeScan:(id)sender
{
  (void)sender;
  [_scanSession resume];
  [self refreshCommandState];
}

- (void)rescan:(id)sender
{
  (void)sender;
  if ([_currentScanPaths count] > 0) {
    [self beginScanPaths:_currentScanPaths];
  } else {
    [self beginScanPath:[self defaultFixturePath]];
  }
}

- (void)stopScan:(id)sender
{
  (void)sender;
  [_scanSession cancel];
  [_refreshSession cancel];
  [_refreshQueue removeAllObjects];
  [self stopDuplicateDetection];
  if ([self isBusy]) {
    [_statusField setStringValue:@"Stopping…"];
  }
}

- (void)openPath:(id)sender
{
  (void)sender;
  NSString *folder = [_currentScanPaths count] == 1 ? [_currentScanPaths objectAtIndex:0] : nil;
  NSArray *paths = [LDSelectTargetPanel runWithInitialFolder:folder];
  if (paths) {
    [self beginScanPaths:paths];
  }
}

- (NSString *)selectedDirectoryPathFromOpenPanel:(NSOpenPanel *)panel
{
  NSArray *filenames = [panel filenames];
  if ([filenames count] > 0) {
    return [filenames objectAtIndex:0];
  }
  if ([panel respondsToSelector:@selector(URL)]) {
    NSURL *url = [panel URL];
    if (url && [url path]) {
      return [url path];
    }
  }
  return [panel filename];
}

#pragma mark - Commands

- (void)zoomIn:(id)sender { [_treemapView zoomIn:sender]; [self refreshCommandState]; }
- (void)zoomOut:(id)sender { [_treemapView zoomOut:sender]; [self refreshCommandState]; }
- (void)resetZoom:(id)sender { [_treemapView resetZoom:sender]; [self refreshCommandState]; }
- (void)selectParent:(id)sender { [_treemapView selectParent:sender]; [self refreshCommandState]; }
- (void)reselectChild:(id)sender { [_treemapView reselectChild:sender]; [self refreshCommandState]; }

- (LDFileNode *)selectedNode
{
  return [_treemapView selectedNode];
}

// The selection of the focused file list; the treemap's selection when the
// treemap has focus. Only nodes still in the tree count: a list can briefly
// hold nodes that a refresh or deletion detached, whose paths are no longer
// complete.
- (NSArray *)selectedNodes
{
  NSMutableArray *inTree = [NSMutableArray array];
  for (LDFileNode *node in [self listedSelectedNodes]) {
    if (_rootNode && [_rootNode isAncestorOf:node]) {
      [inTree addObject:node];
    }
  }
  return inTree;
}

- (NSArray *)listedSelectedNodes
{
  if ([_window firstResponder] == _treemapView) {
    LDFileNode *node = [_treemapView selectedNode];
    return node ? @[node] : @[];
  }
  NSTableView *list = [self activeFileList];
  if (list != _directoryTable) {
    return [self selectedNodesInFileList:list];
  }
  NSMutableArray *nodes = [NSMutableArray array];
  NSIndexSet *rows = [_directoryTable selectedRowIndexes];
  // A nil set would give 0, not NSNotFound, and loop forever: toolbar
  // validation can run from -setToolbar: before the table exists.
  NSUInteger row = rows ? [rows firstIndex] : NSNotFound;
  while (row != NSNotFound) {
    id item = [_directoryTable itemAtRow:(NSInteger)row];
    if (item) {
      [nodes addObject:item];
    }
    row = [rows indexGreaterThanIndex:row];
  }
  if ([nodes count] == 0 && [_treemapView selectedNode]) {
    [nodes addObject:[_treemapView selectedNode]];
  }
  return nodes;
}

- (void)toggleLogicalSize:(id)sender
{
  (void)sender;
  _sizeMetric = (_sizeMetric == LDSizeMetricLogical) ? LDSizeMetricPhysical : LDSizeMetricLogical;
  [[LDPreferences sharedPreferences] setUseLogicalSize:_sizeMetric == LDSizeMetricLogical];
  if (!_rootNode) {
    return;
  }
  LDFileNode *selected = [_treemapView selectedNode];
  [_rootNode sortChildrenByMetric:_sizeMetric];
  [self outlineView:_directoryTable sortDescriptorsDidChange:@[]];
  [self reloadResults];
  [_directoryTable expandItem:_rootNode];
  if (selected) {
    [self revealNodeInTree:selected];
    [_treemapView setSelectedNode:selected];
  }
  [self showSummaryStatus];
  [self updateSelectionField];
}

- (void)toggleGrid:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setTreemapGrid:![preferences treemapGrid]];
}

- (void)toggleLayoutStyle:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setTreemapStyle:[preferences treemapStyle] == 1 ? 0 : 1];
}

#pragma mark - Selection coordination

- (void)revealNodeInTree:(LDFileNode *)node
{
  NSMutableArray *ancestors = [NSMutableArray array];
  LDFileNode *cursor = [node parent];
  while (cursor) {
    [ancestors insertObject:cursor atIndex:0];
    cursor = [cursor parent];
  }
  for (LDFileNode *ancestor in ancestors) {
    [_directoryTable expandItem:ancestor];
  }
  NSInteger row = [_directoryTable rowForItem:node];
  if (row >= 0) {
    _syncingSelection = YES;
    [_directoryTable selectRow:row byExtendingSelection:NO];
    [_directoryTable scrollRowToVisible:row];
    _syncingSelection = NO;
  }
}

- (NSString *)describeNode:(LDFileNode *)node
{
  return [NSString stringWithFormat:@"%@  ·  %@",
          [self displayPath:[node path]],
          [LDSizeFormatter stringForBytes:[node aggregateSizeForMetric:_sizeMetric]]];
}

// WinDirStat's second status pane: the size of everything selected.
- (void)updateSelectionField
{
  unsigned long long total = 0;
  NSArray *nodes = [LDCommandRules topmostNodes:[self selectedNodes]];
  for (LDFileNode *node in nodes) {
    total += [node aggregateSizeForMetric:_sizeMetric];
  }
  NSString *label = _sizeMetric == LDSizeMetricLogical ? @"Logical Size" : @"Physical Size";
  [_selectionField setStringValue:[nodes count] ? [NSString stringWithFormat:@"%@: %@", label, [LDSizeFormatter stringForBytes:total]] : @""];
}

- (void)treemapView:(LDTreemapView *)view didSelectNode:(LDFileNode *)node
{
  (void)view;
  [self revealNodeInTree:node];
  [_statusField setStringValue:[self describeNode:node]];
  [self updateSelectionField];
  [self refreshCommandState];
}

- (void)treemapView:(LDTreemapView *)view didHoverNode:(LDFileNode *)node
{
  (void)view;
  if ([self isBusy]) {
    return;
  }
  if (node) {
    [_statusField setStringValue:[self describeNode:node]];
  } else if ([_treemapView selectedNode]) {
    [_statusField setStringValue:[self describeNode:[_treemapView selectedNode]]];
  } else {
    [self showSummaryStatus];
  }
}

- (void)treemapViewDidChangeZoom:(LDTreemapView *)view
{
  (void)view;
  [self refreshCommandState];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if ([notification object] == _directoryTable) {
    [self directorySelectionDidChange];
  } else if (!_syncingSelection) {
    [self fileListSelectionDidChange:[notification object]];
  }
}

- (void)directorySelectionDidChange
{
  if (_syncingSelection) {
    return;
  }
  NSInteger row = [_directoryTable selectedRow];
  NSInteger clicked = [_directoryTable clickedRow];
  if (clicked >= 0 && [_directoryTable isRowSelected:clicked]) {
    row = clicked;
  }
  LDFileNode *node = row >= 0 ? [_directoryTable itemAtRow:row] : nil;
  [_treemapView setHighlightedExtensionKey:nil];
  [_treemapView setSelectedNode:node];
  if (node) {
    [_statusField setStringValue:[self describeNode:node]];
  }
  [self updateSelectionField];
  [self refreshCommandState];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  // GNUstep's outline view reports through the table view method too.
  if ([notification object] == _directoryTable) {
    [self directorySelectionDidChange];
    return;
  }
  if ([self isFileList:[notification object]]) {
    if (!_syncingSelection) {
      [self fileListSelectionDidChange:[notification object]];
    }
    return;
  }
  if ([notification object] != _extensionTable || _syncingSelection) {
    return;
  }
  NSInteger row = [_extensionTable selectedRow];
  if (row < 0 || row >= (NSInteger)[_extensionRows count]) {
    [_treemapView setHighlightedExtensionKey:nil];
    return;
  }
  LDExtensionStats *stats = [_extensionRows objectAtIndex:row];
  [_treemapView setHighlightedExtensionKey:[stats extensionKey]];
  NSString *pattern = [[stats extensionKey] isEqualToString:@"<none>"] ? @"Files without an extension" : [@"*" stringByAppendingString:[stats displayName]];
  [_statusField setStringValue:[NSString stringWithFormat:@"%@  ·  %lu files, %@",
                                pattern,
                                (unsigned long)[stats fileCount],
                                [LDSizeFormatter stringForBytes:[stats bytesForMetric:_sizeMetric]]]];
}

#pragma mark - Sorting

- (LDTreeSortKey)treeSortKeyForIdentifier:(NSString *)identifier
{
  if ([identifier isEqualToString:@"name"]) {
    return LDTreeSortKeyName;
  }
  if ([identifier isEqualToString:LDColumnFiles]) {
    return LDTreeSortKeyFiles;
  }
  if ([identifier isEqualToString:LDColumnFolders]) {
    return LDTreeSortKeyFolders;
  }
  if ([identifier isEqualToString:LDColumnItems]) {
    return LDTreeSortKeyItems;
  }
  if ([identifier isEqualToString:LDColumnLastChange]) {
    return LDTreeSortKeyLastChange;
  }
  if ([identifier isEqualToString:LDColumnPhysicalSize]) {
    return LDTreeSortKeyPhysicalSize;
  }
  if ([identifier isEqualToString:LDColumnLogicalSize]) {
    return LDTreeSortKeyLogicalSize;
  }
  // Size, Subtree Percentage and Percentage sort by the size the treemap uses.
  return _sizeMetric == LDSizeMetricLogical ? LDTreeSortKeyLogicalSize : LDTreeSortKeyPhysicalSize;
}

- (void)outlineView:(NSOutlineView *)outlineView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
  (void)oldDescriptors;
  if (outlineView != _directoryTable) {
    [self fileListSortDescriptorsDidChange:outlineView];
    return;
  }
  NSSortDescriptor *descriptor = [[outlineView sortDescriptors] firstObject];
  if (!descriptor) {
    return;
  }
  _treeSortKey = [self treeSortKeyForIdentifier:[descriptor key]];
  _treeSortAscending = [descriptor ascending];
  LDTreeSortKey modelKey = _sizeMetric == LDSizeMetricLogical ? LDTreeSortKeyLogicalSize : LDTreeSortKeyPhysicalSize;
  _treeSortIsDefault = (_treeSortKey == modelKey && !_treeSortAscending);
  [_sortedChildrenCache removeAllObjects];
  [outlineView reloadData];
}

// While scanning, children are in the order they were read and sizes still
// grow, so they are sorted here (and again on every live reload).
- (NSArray *)displayChildrenOfNode:(LDFileNode *)node
{
  NSArray *children = [node children];
  if ((_treeSortIsDefault && ![self isScanning]) || [children count] < 2) {
    return children;
  }
  NSArray *sorted = [_sortedChildrenCache objectForKey:node];
  if (!sorted) {
    sorted = [LDTreeSorting sortedNodes:children byKey:_treeSortKey ascending:_treeSortAscending];
    [_sortedChildrenCache setObject:sorted forKey:node];
  }
  return sorted;
}

- (NSArray *)sortedExtensionRows:(NSArray *)rows
{
  NSSortDescriptor *descriptor = [[_extensionTable sortDescriptors] firstObject];
  NSString *key = descriptor ? [descriptor key] : @"bytes";
  BOOL ascending = descriptor ? [descriptor ascending] : NO;
  LDSizeMetric metric = _sizeMetric;
  LDFileTypeDescriptions *descriptions = [LDFileTypeDescriptions sharedDescriptions];
  return [rows sortedArrayUsingComparator:^NSComparisonResult(LDExtensionStats *left, LDExtensionStats *right) {
    NSComparisonResult result = NSOrderedSame;
    if ([key isEqualToString:@"extension"]) {
      result = [[left displayName] caseInsensitiveCompare:[right displayName]];
    } else if ([key isEqualToString:@"description"]) {
      NSString *a = [descriptions descriptionForExtensionKey:[left extensionKey]] ?: @"";
      NSString *b = [descriptions descriptionForExtensionKey:[right extensionKey]] ?: @"";
      result = [a caseInsensitiveCompare:b];
    } else if ([key isEqualToString:@"files"]) {
      result = [@([left fileCount]) compare:@([right fileCount])];
    } else {
      result = [@([left bytesForMetric:metric]) compare:@([right bytesForMetric:metric])];
    }
    if (!ascending) {
      result = (NSComparisonResult)-result;
    }
    return result != NSOrderedSame ? result : [[left extensionKey] compare:[right extensionKey]];
  }];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
  (void)oldDescriptors;
  if ([self isFileList:tableView]) {
    [self fileListSortDescriptorsDidChange:tableView];
    return;
  }
  if (tableView != _extensionTable) {
    return;
  }
  _extensionRows = [self sortedExtensionRows:_extensionRows];
  _syncingSelection = YES;
  [_extensionTable deselectAll:nil];
  _syncingSelection = NO;
  [_treemapView setHighlightedExtensionKey:nil];
  [_extensionTable reloadData];
}

#pragma mark - Table data

- (NSImage *)swatchForColorIndex:(NSUInteger)colorIndex
{
  NSNumber *key = [NSNumber numberWithUnsignedInteger:colorIndex];
  NSImage *image = [_swatchCache objectForKey:key];
  if (image) {
    return image;
  }

  int width = 32;
  int height = 14;
  NSData *pixels = [LDTreemap renderSwatchRGBAWithColor:[LDExtensionColor paletteColorAtIndex:colorIndex]
                                                  width:width
                                                 height:height
                                                options:[_treemapView options]];
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                  pixelsWide:width
                                                                  pixelsHigh:height
                                                               bitsPerSample:8
                                                             samplesPerPixel:4
                                                                    hasAlpha:YES
                                                                    isPlanar:NO
                                                              colorSpaceName:NSDeviceRGBColorSpace
                                                                 bytesPerRow:width * 4
                                                                bitsPerPixel:32];
  memcpy([rep bitmapData], [pixels bytes], [pixels length]);
  image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
  [image addRepresentation:rep];
  [_swatchCache setObject:image forKey:key];
  return image;
}

- (NSImage *)iconNamed:(NSString *)name
{
  NSImage *icon = [_tintedIcons objectForKey:name];
  if (!icon) {
    NSImage *source = [NSImage imageNamed:name];
    icon = source ? [LDIconTextCell image:source tintedWithColor:[NSColor controlTextColor]] : nil;
    if (icon) {
      [_tintedIcons setObject:icon forKey:name];
    }
  }
  return icon;
}

- (NSImage *)iconForNode:(LDFileNode *)node
{
  LDHardLinkItemType hardLinkItem = LDHardLinkItemTypeOfNode(node);
  if (hardLinkItem != LDHardLinkItemNone && hardLinkItem != LDHardLinkItemReference) {
    return [self iconNamed:@"edit-copy-symbolic"];
  }
  NSImage *native = [LDPlatformUI fileIconForNode:node];
  if (native) {
    return native;
  }
  if ([node isComputer]) {
    return [self iconNamed:@"computer-symbolic"];
  }
  if ([node isMountPoint] || [[node parent] isComputer]) {
    return [self iconNamed:@"drive-harddisk-symbolic"];
  }
  if ([node kind] == LDFileNodeKindFreeSpace) {
    return [self iconNamed:@"radio-symbolic"];
  }
  if ([node kind] == LDFileNodeKindUnknown) {
    return [self iconNamed:@"dialog-question-symbolic"];
  }
  switch ([node kind]) {
    case LDFileNodeKindDirectory: return [self iconNamed:@"folder-symbolic"];
    case LDFileNodeKindSymlink: return [self iconNamed:@"insert-link-symbolic"];
    default: return [self iconNamed:@"text-x-generic-symbolic"];
  }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  if (tableView == _extensionTable) {
    return (NSInteger)[_extensionRows count];
  }
  return [self isFileList:tableView] ? (NSInteger)[[self rowsOfFileList:tableView] count] : 0;
}

- (NSString *)percentStringForFraction:(double)fraction
{
  return [NSString stringWithFormat:@"%.1f%%", fraction * 100.0];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
  NSString *identifier = [tableColumn identifier];
  if ([self isFileList:tableView]) {
    return [self fileListValueForColumn:identifier item:[[self rowsOfFileList:tableView] objectAtIndex:(NSUInteger)row]];
  }
  LDExtensionStats *stats = [_extensionRows objectAtIndex:row];
  if ([identifier isEqualToString:@"extension"]) {
    return [stats displayName];
  }
  if ([identifier isEqualToString:@"color"]) {
    return [self swatchForColorIndex:[stats colorIndex]];
  }
  if ([identifier isEqualToString:@"description"]) {
    return [[LDFileTypeDescriptions sharedDescriptions] descriptionForExtensionKey:[stats extensionKey]] ?: @"";
  }
  if ([identifier isEqualToString:@"bytes"]) {
    return [LDSizeFormatter stringForBytes:[stats bytesForMetric:_sizeMetric]];
  }
  if ([identifier isEqualToString:@"percent"]) {
    unsigned long long total = [_rootNode aggregateSizeForMetric:_sizeMetric];
    return [self percentStringForFraction:total ? (double)[stats bytesForMetric:_sizeMetric] / (double)total : 0.0];
  }
  return [NSString stringWithFormat:@"%lu", (unsigned long)[stats fileCount]];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
  if (outlineView == _duplicatesTable) {
    return item ? (NSInteger)[[item nodes] count] : (NSInteger)[_duplicateGroups count];
  }
  if (!_rootNode) {
    return 0;
  }
  if (!item) {
    return 1;
  }
  return (NSInteger)[[self displayChildrenOfNode:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
  if (outlineView == _duplicatesTable) {
    return item ? [[item nodes] objectAtIndex:(NSUInteger)index] : [_duplicateGroups objectAtIndex:(NSUInteger)index];
  }
  if (!item) {
    return _rootNode;
  }
  return [[self displayChildrenOfNode:item] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
  if (outlineView == _duplicatesTable) {
    return [item isKindOfClass:[LDDuplicateGroup class]];
  }
  return item && [[self displayChildrenOfNode:item] count] > 0;
}

// A node's share of its parent, as WinDirStat's Percentage column shows it.
- (double)fractionOfParentForNode:(LDFileNode *)node
{
  LDFileNode *parent = [node parent];
  if (!parent) {
    return 1.0;
  }
  unsigned long long parentBytes = [parent aggregateSizeForMetric:_sizeMetric];
  return parentBytes ? (double)[node aggregateSizeForMetric:_sizeMetric] / (double)parentBytes : 0.0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
  if (outlineView == _duplicatesTable) {
    return [self fileListValueForColumn:[tableColumn identifier] item:item];
  }
  LDFileNode *node = item;
  NSString *identifier = [tableColumn identifier];
  if ([identifier isEqualToString:@"name"]) {
    return (node == _rootNode || [[node parent] isComputer]) ? [self displayPath:[node path]] : [node displayName];
  }
  if ([identifier isEqualToString:@"subtree"]) {
    return nil;
  }
  if ([identifier isEqualToString:@"percent"]) {
    // WinDirStat shows the time spent on the root while scanning.
    if (node == _rootNode && [self isScanning] && [[LDPreferences sharedPreferences] showTimeSpent]) {
      NSInteger seconds = (NSInteger)[_scanSession elapsedTime];
      return [NSString stringWithFormat:@"[%ld:%02ld]", (long)(seconds / 60), (long)(seconds % 60)];
    }
    return [self percentStringForFraction:[self fractionOfParentForNode:node]];
  }
  if ([identifier isEqualToString:LDColumnPhysicalSize]) {
    return [self physicalSizeStringForNode:node];
  }
  if ([identifier isEqualToString:LDColumnLogicalSize]) {
    return [self logicalSizeStringForNode:node];
  }
  BOOL pseudo = LDIsHardLinkItem(node);
  if ([identifier isEqualToString:LDColumnLastChange]) {
    NSTimeInterval time = [node aggregateModificationTime];
    return time > 0 ? [_dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]] : @"";
  }
  if ([identifier isEqualToString:LDColumnAttributes]) {
    return pseudo ? @"" : [LDFileAttributes attributeStringForNode:node];
  }
  if ([identifier isEqualToString:LDColumnOwner]) {
    return pseudo ? @"" : [self ownerOfNode:node];
  }
  // Items, Files and Folders are blank for files and pseudo-items, as in
  // WinDirStat.
  if ([node kind] != LDFileNodeKindDirectory || pseudo) {
    return @"";
  }
  NSUInteger folders = [node directoryCount] > 0 ? [node directoryCount] - 1 : 0;
  if ([identifier isEqualToString:LDColumnFiles]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)[node fileCount]];
  }
  if ([identifier isEqualToString:LDColumnFolders]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)folders];
  }
  if ([identifier isEqualToString:LDColumnItems]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)([node fileCount] + folders)];
  }
  return @"";
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
  if (outlineView != _directoryTable) {
    return;
  }
  LDFileNode *node = item;
  NSString *identifier = [tableColumn identifier];
  if ([identifier isEqualToString:@"subtree"]) {
    LDPercentageBarCell *bar = cell;
    [bar setFraction:[self fractionOfParentForNode:node] depth:[node depth]];
    BOOL pending = [node isScanPending];
    BOOL animate = [[LDPreferences sharedPreferences] pacmanAnimation];
    [bar setShowsPacman:pending && animate time:[self pacmanTime]];
    [bar setReadJobs:(pending && !animate) ? [node pendingScanCount] : 0];
    return;
  }
  if ([identifier isEqualToString:@"name"]) {
    [(LDIconTextCell *)cell setIcon:[self iconForNode:node]];
  }
  // Entries that could not be read or were not entered are dimmed.
  BOOL dimmed = [node error] == LDFileNodeErrorDirectoryUnreadable
    || [node error] == LDFileNodeErrorStatFailed
    || [node isMountPoint];
  if ([cell respondsToSelector:@selector(setTextColor:)]) {
    [cell setTextColor:dimmed ? [NSColor disabledControlTextColor] : [NSColor controlTextColor]];
  }
}

// Looked up on demand (the scan does not store owners) and cached per node.
- (NSString *)ownerOfNode:(LDFileNode *)node
{
  if ([node isSpaceItem]) {
    return @"";
  }
  NSString *owner = [_ownerCache objectForKey:node];
  if (!owner) {
    owner = [LDFileAttributes ownerOfPath:[node pathData]] ?: @"";
    [_ownerCache setObject:owner forKey:node];
  }
  return owner;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  (void)sender;
  return YES;
}

- (void)dealloc
{
  [_busyTimer invalidate];
  [_memoryTimer invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
