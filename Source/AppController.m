#import "AppController.h"
#import "LDLocalization.h"
#import "AppController+Private.h"
#import "LDCommandLine.h"
#import "LDColumnChooser.h"
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
#import "LDScanResults.h"
#import "LDProfiling.h"
#import "LDSizeFormatter.h"
#import "LDSpaceItems.h"
#import "LDSystemInfo.h"
#import "LDTreeCells.h"
#import "LDTreemapLayout.h"
#import "LDTreemapView.h"
#import "LDUpdates.h"
#import "LDDesktop.h"
#import "LDFileOperations.h"
#import "LDMainWindow.h"
#import "LDScanClock.h"
#import "LDScanProgress.h"
#import "LDTabCycle.h"

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
static const CGFloat LDProgressBarWidth = 160.0;
// Empty Trash's label is measured at most this often, walking at most this
// many entries.
static const NSTimeInterval LDTrashMeasureInterval = 10.0;
static const NSUInteger LDTrashMeasureEntryLimit = 20000;
// Columns are fitted to at most this many rows.
static const NSInteger LDColumnFitRowLimit = 1000;

static NSString *const LDHelpURL = @"https://github.com/danjboyd/LinDirStat";
static NSString *const LDReportBugURL = @"https://github.com/danjboyd/LinDirStat/issues/new";

@interface AppController (TableData) <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarDelegate, NSSplitViewDelegate, LDTreemapViewDelegate>
@end

// Scan progress, window chrome and keyboard state.
@interface AppController () <LDMainWindowKeyHandler>
{
  NSBox *_statusSeparator;
  NSProgressIndicator *_progressBar;
  unsigned long long _progressRange;
  NSString *_titleBase;
  NSString *_titlePrefix;
  NSTimeInterval _pacmanResumedAt;
  NSMenuItem *_emptyTrashItem;
  NSTimeInterval _trashMeasuredAt;
  BOOL _measuringTrash;
  NSTimeInterval _profileStopPressedAt;
}
- (LDScanResultsRequest *)scanResultsRequest;
- (void)releaseInBackground:(NSArray *)objects;
- (void)startProfilingScan:(LDScanSession *)session;
- (void)logProfileOfScanCompletion:(NSTimeInterval)started;
- (void)reloadResultsWithScanResults:(LDScanResults *)results treemapIsCurrent:(BOOL)treemapIsCurrent;
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
  [self setUpMainWindow];
  [_updates startWithWindow:_window];
  [self startLayoutDumpIfRequested];
  LDCommandLine *commandLine = [LDCommandLine processCommandLine];
  if ([commandLine loadFromCSVPath]) {
    [self loadResultsFromCSVFile:[commandLine loadFromCSVPath]];
  } else {
    [self beginScanPaths:[self initialScanPaths:commandLine]];
  }
}

// The window and its state, without starting a scan (the UI tests start
// their own).
- (void)setUpMainWindow
{
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

  NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
  _window = [[LDMainWindow alloc] initWithContentRect:NSMakeRect(100, 100, 1280, 820)
                                            styleMask:style
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  // _window owns the window; released when closed as well, closing it
  // released it twice and the app crashed on its way out.
  [_window setReleasedWhenClosed:NO];
  [(LDMainWindow *)_window setKeyHandler:self];
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
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(filtersDidChange:)
                                               name:LDOptionsFiltersDidChangeNotification
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
  [self addItemTo:appMenu title:LDLocalized(@"Preferences") action:@selector(showPreferences:) key:@"," target:self];
  [self addItemTo:appMenu title:LDLocalized(@"About LinDirStat") action:@selector(orderFrontStandardAboutPanel:) key:nil target:NSApp];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:appMenu title:LDLocalized(@"Quit") action:@selector(terminate:) key:@"q" target:NSApp];

  NSMenu *fileMenu = [self addSubmenuTitled:LDLocalized(@"File") to:mainMenu];
  [self addItemTo:fileMenu title:LDLocalized(@"Select Target…") action:@selector(openPath:) key:@"o" target:self];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *loadCSV = (NSMenuItem *)[self addItemTo:fileMenu title:LDLocalized(@"Load Results From CSV…") action:@selector(loadResultsFromCSV:) key:@"l" target:self];
  [loadCSV setKeyEquivalentModifierMask:NSControlKeyMask | NSAlternateKeyMask];
  NSMenuItem *saveCSV = (NSMenuItem *)[self addItemTo:fileMenu title:LDLocalized(@"Save Results To CSV…") action:@selector(saveResultsToCSV:) key:@"s" target:self];
  [saveCSV setKeyEquivalentModifierMask:NSControlKeyMask | NSAlternateKeyMask];
  [self addItemTo:fileMenu title:LDLocalized(@"Save Duplicates To CSV…") action:@selector(saveDuplicatesToCSV:) key:nil target:self];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *refreshAll = (NSMenuItem *)[self addItemTo:fileMenu title:LDLocalized(@"Refresh All") action:@selector(rescan:) key:[self functionKey:NSF5FunctionKey] target:self];
  [refreshAll setKeyEquivalentModifierMask:NSShiftKeyMask];
  NSMenuItem *refreshSelected = (NSMenuItem *)[self addItemTo:fileMenu title:LDLocalized(@"Refresh Selected") action:@selector(refreshSelected:) key:[self functionKey:NSF5FunctionKey] target:self];
  [refreshSelected setKeyEquivalentModifierMask:0];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:fileMenu title:LDLocalized(@"Suspend Scan") action:@selector(suspendScan:) key:nil target:self];
  [self addItemTo:fileMenu title:LDLocalized(@"Resume Scan") action:@selector(resumeScan:) key:nil target:self];
  [self addItemTo:fileMenu title:LDLocalized(@"Stop Scan") action:@selector(stopScan:) key:@"." target:self];

  NSMenu *editMenu = [self addSubmenuTitled:LDLocalized(@"Edit") to:mainMenu];
  [self addItemTo:editMenu title:LDLocalized(@"Copy Path") action:@selector(copyPath:) key:@"c" target:self];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:editMenu title:LDLocalized(@"Search…") action:@selector(search:) key:@"f" target:self];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:editMenu title:LDLocalized(@"Add to Exclusion Filter") action:@selector(excludeItem:) key:nil target:self];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:editMenu title:LDLocalized(@"Compute Hash") action:@selector(computeHash:) key:@"h" target:self];

  NSMenu *cleanupMenu = [self addSubmenuTitled:LDLocalized(@"Clean Up") to:mainMenu];
  [self populateCleanupMenu:cleanupMenu forTreemap:NO];
  _cleanupMenu = cleanupMenu;
  // GNUstep's NSMenuDelegate lists optional methods as required.
  [_cleanupMenu setDelegate:(id)self];

  NSMenu *treemapMenu = [self addSubmenuTitled:LDLocalized(@"Treemap") to:mainMenu];
  [self addItemTo:treemapMenu title:LDLocalized(@"Zoom In") action:@selector(zoomIn:) key:@"+" target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"Zoom Out") action:@selector(zoomOut:) key:@"-" target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"Reset Zoom") action:@selector(resetZoom:) key:@"0" target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"Reselect Child") action:@selector(reselectChild:) key:@"=" target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"Select Parent") action:@selector(selectParent:) key:@"u" target:self];
  [treemapMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:treemapMenu title:LDLocalized(@"Use Logical Size") action:@selector(toggleLogicalSize:) key:@"l" target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"Show Absolute Percentages") action:@selector(toggleAbsolutePercentages:) key:nil target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"Show Grid") action:@selector(toggleGrid:) key:nil target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"Show Folder Frames") action:@selector(toggleFolderFrames:) key:nil target:self];
  [self addItemTo:treemapMenu title:LDLocalized(@"SequoiaView Layout") action:@selector(toggleLayoutStyle:) key:nil target:self];

  NSMenu *toolsMenu = [self addSubmenuTitled:LDLocalized(@"Tools") to:mainMenu];
  [self addItemTo:toolsMenu title:LDLocalized(@"Start File Watcher") action:@selector(toggleFileWatcher:) key:nil target:self];
  [toolsMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:toolsMenu title:LDLocalized(@"Change Folder Dates to Last Change") action:@selector(setFolderDates:) key:nil target:self];

  NSMenu *optionsMenu = [self addSubmenuTitled:LDLocalized(@"Options") to:mainMenu];
  [[self addItemTo:optionsMenu title:LDLocalized(@"Show Free Space") action:@selector(toggleFreeSpace:) key:[self functionKey:NSF6FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [[self addItemTo:optionsMenu title:LDLocalized(@"Show Unknown") action:@selector(toggleUnknown:) key:[self functionKey:NSF7FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [optionsMenu addItem:[NSMenuItem separatorItem]];
  [[self addItemTo:optionsMenu title:LDLocalized(@"Show File Types") action:@selector(toggleFileTypes:) key:[self functionKey:NSF8FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [self addItemTo:optionsMenu title:LDLocalized(@"Group Unregistered Types") action:@selector(toggleGroupUnregisteredTypes:) key:nil target:self];
  [[self addItemTo:optionsMenu title:LDLocalized(@"Show Treemap") action:@selector(toggleTreemap:) key:[self functionKey:NSF9FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [[self addItemTo:optionsMenu title:LDLocalized(@"Show Toolbar") action:@selector(toggleToolBar:) key:[self functionKey:NSF10FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [self addItemTo:optionsMenu title:LDLocalized(@"Large Toolbar Icons") action:@selector(toggleLargeToolBar:) key:nil target:self];
  [[self addItemTo:optionsMenu title:LDLocalized(@"Show Status Bar") action:@selector(toggleStatusBar:) key:[self functionKey:NSF11FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [optionsMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:optionsMenu title:LDLocalized(@"Preferences") action:@selector(showPreferences:) key:nil target:self];

  NSMenu *helpMenu = [self addSubmenuTitled:LDLocalized(@"Help") to:mainMenu];
  [[self addItemTo:helpMenu title:LDLocalized(@"LinDirStat Help") action:@selector(showHelp:) key:[self functionKey:NSF1FunctionKey] target:self]
    setKeyEquivalentModifierMask:0];
  [self addItemTo:helpMenu title:LDLocalized(@"Report a Bug…") action:@selector(reportBug:) key:nil target:self];
  // Only a copy that can update itself (the AppImage) offers it.
  _updates = [LDUpdates packagedUpdates];
  if (_updates) {
    [helpMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:helpMenu title:LDLocalized(@"Check for Updates…") action:@selector(checkForUpdates:) key:nil target:_updates];
  }

  [LDPlatformUI completeMainMenu:mainMenu applicationMenu:appMenu preferencesTarget:self];
  [NSApp setMainMenu:mainMenu];
}

// WinDirStat recalculates without rescanning; so does LinDirStat. While a
// scan or refresh runs the setting is applied when it finishes.
- (void)toggleFreeSpace:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowFreeSpace:![preferences showFreeSpace]];
  [self applySpaceItems];
}

- (void)toggleUnknown:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowUnknown:![preferences showUnknown]];
  [self applySpaceItems];
}

- (void)applySpaceItems
{
  if (_rootNode && ![self isBusy]) {
    [self updateSpaceItems];
    [self didChangeTree];
    [self showSummaryStatus];
  }
}

// Adds, removes or recomputes <Free Space> and <Unknown> under each volume
// root for the Options menu settings.
- (BOOL)updateSpaceItems
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSArray *volumes = [LDSpaceItems volumeNodesOfRoot:_rootNode];
  NSArray *removed = [LDSpaceItems updateVolumes:volumes
                                   showFreeSpace:[preferences showFreeSpace]
                                     showUnknown:[preferences showUnknown]
                                           usage:[LDSpaceItems diskUsageQuery]
                                          metric:_sizeMetric];
  [_detachedSubtrees addObjectsFromArray:removed];
  return [volumes count] > 0 && ([removed count] > 0 || [preferences showFreeSpace] || [preferences showUnknown]);
}

- (void)toggleFileTypes:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowFileTypes:![preferences showFileTypes]];
}

// WinDirStat 2.8 (04b336dc, 6813c201): regroups and recolours the
// extensions of the finished scan, keeping the selection and zoom.
- (void)toggleGroupUnregisteredTypes:(id)sender
{
  (void)sender;
  if (![self validateAction:@selector(toggleGroupUnregisteredTypes:)]) {
    return;
  }
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setGroupUnregisteredTypes:![preferences groupUnregisteredTypes]];
  [self didChangeTree];
}

- (void)toggleTreemap:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowTreemap:![preferences showTreemap]];
}

- (void)toggleToolBar:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowToolBar:![preferences showToolBar]];
}

- (void)toggleLargeToolBar:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setLargeToolBar:![preferences largeToolBar]];
}

- (void)toggleStatusBar:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setShowStatusBar:![preferences showStatusBar]];
}

- (void)openWebAddress:(NSString *)address
{
  [LDDesktop runFirstSuccessfulCommand:[LDDesktop openCommandsForURL:address] inDirectory:nil completion:^(BOOL succeeded) {
    if (!succeeded) {
      [self showStatus:[NSString stringWithFormat:LDLocalized(@"Could not open %@"), address]];
    }
  }];
}

- (void)showHelp:(id)sender
{
  (void)sender;
  [self openWebAddress:LDHelpURL];
}

- (void)reportBug:(id)sender
{
  (void)sender;
  [self openWebAddress:LDReportBugURL];
}

// WinDirStat's View options: the toolbar, its icon size and the status bar.
- (void)applyChromeVisibility
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSToolbar *toolbar = [_window toolbar];
  NSToolbarSizeMode sizeMode = [preferences largeToolBar] ? NSToolbarSizeModeRegular : NSToolbarSizeModeSmall;
  if ([toolbar sizeMode] != sizeMode) {
    // The theme decides how large the icons are drawn in each size mode.
    [toolbar setSizeMode:sizeMode];
  }
  if ([toolbar isVisible] != [preferences showToolBar]) {
    [toolbar setVisible:[preferences showToolBar]];
  }
  BOOL statusShown = [preferences showStatusBar];
  if ([_statusField isHidden] == statusShown) {
    for (NSView *view in @[_statusSeparator, _statusField, _selectionField, _memoryField]) {
      [view setHidden:!statusShown];
    }
    [self updateProgressWidgets];
    NSRect content = [[_window contentView] bounds];
    CGFloat bottom = statusShown ? LDStatusBarHeight + 1 : 0.0;
    // The treemap takes up or gives back the status bar's height.
    CGFloat topHeight = NSHeight([_topSplit frame]);
    [_mainSplit setFrame:NSMakeRect(0, bottom, content.size.width, content.size.height - bottom)];
    if ([[_mainSplit subviews] count] > 1) {
      [_mainSplit setPosition:topHeight ofDividerAtIndex:0];
    }
    [[_window contentView] setNeedsDisplay:YES];
    [self fitFlexibleColumns];
  }
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
    [self addItemTo:menu title:LDLocalized(@"Zoom In") action:@selector(zoomIn:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Zoom Out") action:@selector(zoomOut:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Reset Zoom") action:@selector(resetZoom:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Reselect Child") action:@selector(reselectChild:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Select Parent") action:@selector(selectParent:) key:nil target:self];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:menu title:LDLocalized(@"Group Unregistered Types") action:@selector(toggleGroupUnregisteredTypes:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Show Folder Frames") action:@selector(toggleFolderFrames:) key:nil target:self];
    [menu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:menu title:LDLocalized(@"Copy Path") action:@selector(copyPath:) key:nil target:self];
    [self addItemTo:menu title:[LDPlatformUI showInFileManagerTitle] action:@selector(revealItem:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Open Terminal Here") action:@selector(openTerminal:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Add to Exclusion Filter") action:@selector(excludeItem:) key:nil target:self];
    return;
  }
  BOOL isMainMenu = ([menu supermenu] != nil);
  [self addItemTo:menu title:LDLocalized(@"Open") action:@selector(openItem:) key:nil target:self];
  [self addItemTo:menu title:[LDPlatformUI showInFileManagerTitle] action:@selector(revealItem:) key:isMainMenu ? @"e" : nil target:self];
  [self addItemTo:menu title:LDLocalized(@"Open Terminal Here") action:@selector(openTerminal:) key:isMainMenu ? @"t" : nil target:self];
  if (!isMainMenu) {
    [self addItemTo:menu title:LDLocalized(@"Copy Path") action:@selector(copyPath:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Refresh Selected") action:@selector(refreshSelected:) key:nil target:self];
  }
  [self addItemTo:menu title:LDLocalized(@"Properties") action:@selector(showProperties:) key:isMainMenu ? @"i" : nil target:self];
  if (!isMainMenu) {
    [self addItemTo:menu title:LDLocalized(@"Add to Exclusion Filter") action:@selector(excludeItem:) key:nil target:self];
  }
  [menu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:menu title:LDLocalized(@"Move to Trash") action:@selector(moveToTrash:) key:nil target:self];
  [self addItemTo:menu title:LDLocalized(@"Delete Permanently…") action:@selector(deletePermanently:) key:nil target:self];
  if (isMainMenu) {
    _emptyTrashItem = [self addItemTo:menu title:LDLocalized(@"Empty Trash…") action:@selector(emptyTrash:) key:nil target:self];
  }
  [self addItemTo:menu title:LDLocalized(@"Remove Empty Folders") action:@selector(removeEmptyFolders:) key:nil target:self];
  [self addItemTo:menu title:LDLocalized(@"Empty Folder…") action:@selector(emptyFolder:) key:nil target:self];
  [self addItemTo:menu title:LDLocalized(@"Move To…") action:@selector(moveItemsTo:) key:isMainMenu ? @"m" : nil target:self];
  [self addItemTo:menu title:LDLocalized(@"Deduplicate with Hardlink") action:@selector(deduplicateWithHardLinks:) key:nil target:self];
  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *custom = (NSMenuItem *)[menu addItemWithTitle:LDLocalized(@"Custom Cleanup") action:NULL keyEquivalent:@""];
  [custom setSubmenu:[self customCleanupMenu]];
  // WinDirStat's "Windows Explorer Menu" (windirstat.rc): the applications
  // that open the selection. The main menu fills it each time it opens;
  // context menus are built for the selection they appear on.
  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *openWith = (NSMenuItem *)[menu addItemWithTitle:LDLocalized(@"Open With") action:NULL keyEquivalent:@""];
  NSMenu *openWithMenu = [[NSMenu alloc] initWithTitle:LDLocalized(@"Open With")];
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
  NSMenuItem *custom = (NSMenuItem *)[_cleanupMenu itemWithTitle:LDLocalized(@"Custom Cleanup")];
  [custom setSubmenu:[self customCleanupMenu]];
}

- (void)preferencesDidChange:(NSNotification *)notification
{
  (void)notification;
  [self rebuildCustomCleanupMenus];
  [self applyDisplayPreferences];
}

// Before the Clean Up menu shows (GNUstep asks on every menu update): the
// trash is measured again in the background if the last count is stale, and
// Empty Trash shows it (WinDirStat's UpdateCleanupMenu); Open With is filled
// for the selection.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (menu != _cleanupMenu) {
    return;
  }
  [self measureTrashIfStale];
  [self fillOpenWithIfSelectionChanged];
}

- (void)fillOpenWithIfSelectionChanged
{
  NSArray *nodes = [self selectedNodes];
  BOOL unchanged = [nodes count] == [_openWithNodes count];
  for (NSUInteger i = 0; unchanged && i < [nodes count]; i++) {
    unchanged = [nodes objectAtIndex:i] == [_openWithNodes objectAtIndex:i];
  }
  if (unchanged) {
    return;
  }
  _openWithNodes = nodes;
  [self fillOpenWithMenu:[[_cleanupMenu itemWithTitle:LDLocalized(@"Open With")] submenu] forNodes:nodes];
}

- (void)measureTrashIfStale
{
  if (_measuringTrash || [NSDate timeIntervalSinceReferenceDate] - _trashMeasuredAt < LDTrashMeasureInterval) {
    return;
  }
  _measuringTrash = YES;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    NSUInteger items = 0;
    unsigned long long bytes = 0;
    BOOL complete = YES;
    [LDFileOperations measureTrashContents:[LDFileOperations trashContentDirectories]
                                entryLimit:LDTrashMeasureEntryLimit
                                     items:&items
                                     bytes:&bytes
                                  complete:&complete];
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_measuringTrash = NO;
      self->_trashMeasuredAt = [NSDate timeIntervalSinceReferenceDate];
      [self->_emptyTrashItem setTitle:[LDCommandRules emptyTrashTitleForItems:items bytes:bytes complete:complete]];
    });
  });
}

// The tree's context menu starts with Expand or Collapse for rows that have
// children (TreeListControl.cpp OnContextMenu). AppKit has no default
// (bold) menu item, so it is only placed first.
- (NSMenu *)contextMenuForListView:(NSTableView *)view
{
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
  // The extension list's own menu (WinDirStat's OnContextMenu there).
  if (view == _extensionTable) {
    // Search is the default (double-click) item; AppKit has no bold default.
    NSString *search = [NSString stringWithFormat:@"%@ - %@", LDLocalized(@"Extension"), LDLocalized(@"Search")];
    [self addItemTo:menu title:search action:@selector(searchExtension:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Group Unregistered Types") action:@selector(toggleGroupUnregisteredTypes:) key:nil target:self];
    [self addItemTo:menu title:LDLocalized(@"Add to Exclusion Filter") action:@selector(excludeExtension:) key:nil target:self];
    return menu;
  }
  if (view == _directoryTable) {
    NSPoint point = [view convertPoint:[[NSApp currentEvent] locationInWindow] fromView:nil];
    NSInteger row = [view rowAtPoint:point];
    id item = row >= 0 ? [_directoryTable itemAtRow:row] : nil;
    if (item && [[self displayChildrenOfNode:item] count] > 0) {
      BOOL expanded = [_directoryTable isItemExpanded:item];
      NSMenuItem *toggle = [self addItemTo:menu title:expanded ? LDLocalized(@"Collapse") : LDLocalized(@"Expand")
                                    action:@selector(toggleExpansion:) key:nil target:self];
      [toggle setRepresentedObject:item];
      [menu addItem:[NSMenuItem separatorItem]];
    }
  }
  [self populateCleanupMenu:menu forTreemap:NO];
  return menu;
}

- (void)toggleExpansion:(id)sender
{
  id item = [sender representedObject];
  if ([_directoryTable isItemExpanded:item]) {
    [_directoryTable collapseItem:item];
  } else {
    [_directoryTable expandItem:item];
  }
}

- (void)listViewOpenSelection:(NSTableView *)view
{
  // Rows of the extension list are not files.
  if (view == _extensionTable) {
    return;
  }
  [self openItem:nil];
}

- (void)listView:(NSTableView *)view deleteSelectionPermanently:(BOOL)permanently
{
  if (view == _extensionTable) {
    return;
  }
  [self deleteNodes:[self selectedNodes] permanently:permanently];
}

#pragma mark - Keyboard

// Ctrl+F1-F4 show the file tabs, and Tab cycles through the tabs and the
// extension list (WinDirStat's accelerators and FileTabbedView CycleTab).
- (BOOL)mainWindowHandleKeyDown:(NSEvent *)event
{
  NSString *characters = [event charactersIgnoringModifiers];
  if ([characters length] != 1) {
    return NO;
  }
  unichar key = [characters characterAtIndex:0];
  NSUInteger modifiers = [event modifierFlags] & (NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask | NSShiftKeyMask);
  // GNUstep can map the Ctrl key to the Command modifier (as its menus show).
  BOOL control = modifiers == NSControlKeyMask || modifiers == NSCommandKeyMask;
  BOOL functionKey = control && key >= NSF1FunctionKey && key <= NSF4FunctionKey;
  BOOL commandDigit = [LDPlatformUI usesCommandDigitsForFileTabs] && modifiers == NSCommandKeyMask
    && key >= '1' && key <= '4';
  if (functionKey || commandDigit) {
    NSArray *tabs = @[_allFilesTab, _largestTab, _duplicatesTab, _searchTab];
    NSTabViewItem *tab = [tabs objectAtIndex:functionKey ? key - NSF1FunctionKey : key - '1'];
    if ([[_fileTabs tabViewItems] indexOfObjectIdenticalTo:tab] != NSNotFound) {
      [_fileTabs selectTabViewItem:tab];
      [_window makeFirstResponder:[self activeFileList]];
    }
    return YES;
  }
  BOOL backTab = key == NSBackTabCharacter || (key == NSTabCharacter && modifiers == NSShiftKeyMask);
  if ((key == NSTabCharacter && modifiers == 0) || backTab) {
    [self moveFocusForward:!backTab];
    return YES;
  }
  return NO;
}

- (void)moveFocusForward:(BOOL)forward
{
  NSArray *tabs = [_fileTabs tabViewItems];
  NSResponder *responder = [_window firstResponder];
  BOOL extensionsShown = [[_topSplit subviews] indexOfObjectIdenticalTo:_extensionScroll] != NSNotFound;
  NSInteger current = LDFocusOther;
  if (responder == _extensionTable) {
    current = LDFocusExtensionList;
  } else if (responder == [self activeFileList]) {
    current = (NSInteger)[tabs indexOfObjectIdenticalTo:[_fileTabs selectedTabViewItem]];
  }
  NSInteger next = [LDTabCycle nextFocusFrom:current
                                 visibleTabs:[tabs count]
                       extensionListVisible:extensionsShown
                                     forward:forward];
  if (next == LDFocusExtensionList) {
    [_window makeFirstResponder:_extensionTable];
  } else if (next >= 0) {
    NSTabViewItem *tab = [tabs objectAtIndex:(NSUInteger)next];
    if ([_fileTabs selectedTabViewItem] != tab) {
      [_fileTabs selectTabViewItem:tab];
    }
    [_window makeFirstResponder:[self activeFileList]];
  }
}

- (BOOL)isScanning
{
  return _scanSession && ![_scanSession isFinished];
}

// While scanning, the scan's own clock, which stops while it is suspended
// and so freezes the pacmen as WinDirStat does.
- (NSTimeInterval)pacmanTime
{
  if ([self isScanning]) {
    return [_scanSession elapsedTime];
  }
  return [NSDate timeIntervalSinceReferenceDate] - _pacmanEpoch;
}

- (BOOL)isBusy
{
  return [self isScanning] || _scanAwaitingAdoption || _refreshQueue != nil || _fileOperationRunning;
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
    NSStringFromSelector(@selector(excludeItem:)): @(LDCommandExcludeItem),
    NSStringFromSelector(@selector(removeEmptyFolders:)): @(LDCommandRemoveEmptyFolders),
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
  // With nothing selected it covers the whole tree.
  if (action == @selector(setFolderDates:)) {
    return _rootNode != nil && ![self isBusy] && !_loadedFile
      && [[LDCommandRules foldersForDatesIn:[self selectedNodes] rootNode:_rootNode] count] > 0;
  }
  if (action == @selector(deduplicateWithHardLinks:)) {
    return [[self hardLinkPairs] count] > 0;
  }
  if (action == @selector(excludeExtension:)) {
    return _rootNode != nil && ![self isBusy] && [self exclusionPatternForSelectedExtension] != nil;
  }
  if (action == @selector(searchExtension:)) {
    return _rootNode != nil && ![self isBusy] && [self selectedExtensionKey] != nil;
  }
  // Only once the scan has settled, with the extension list shown.
  if (action == @selector(toggleGroupUnregisteredTypes:)) {
    return _rootNode != nil && ![self isBusy] && [[LDPreferences sharedPreferences] showFileTypes];
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
  if (action == @selector(toggleGroupUnregisteredTypes:)) {
    [item setState:[[LDPreferences sharedPreferences] groupUnregisteredTypes] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleTreemap:)) {
    [item setState:[[LDPreferences sharedPreferences] showTreemap] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleToolBar:)) {
    [item setState:[[LDPreferences sharedPreferences] showToolBar] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleLargeToolBar:)) {
    [item setState:[[LDPreferences sharedPreferences] largeToolBar] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleStatusBar:)) {
    [item setState:[[LDPreferences sharedPreferences] showStatusBar] ? NSOnState : NSOffState];
  }
  if (action == @selector(toggleFileWatcher:)) {
    [item setTitle:[self isFileWatcherOn] ? LDLocalized(@"Stop File Watcher") : LDLocalized(@"Start File Watcher")];
  }
  if (action == @selector(toggleLogicalSize:)) {
    [item setState:_sizeMetric == LDSizeMetricLogical ? NSOnState : NSOffState];
  } else if (action == @selector(toggleAbsolutePercentages:)) {
    [item setState:[[LDPreferences sharedPreferences] useAbsolutePercentages] ? NSOnState : NSOffState];
  } else if (action == @selector(toggleFolderFrames:)) {
    [item setState:[[LDPreferences sharedPreferences] treemapShowFolderFrames] ? NSOnState : NSOffState];
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
    LDToolbarSelectTarget: @[LDLocalized(@"Select Target"), LDLocalized(@"Scan a folder"), @"document-open-symbolic", NSStringFromSelector(@selector(openPath:))],
    LDToolbarRefresh: @[LDLocalized(@"Refresh"), LDLocalized(@"Scan the folder again"), @"view-refresh-symbolic", NSStringFromSelector(@selector(rescan:))],
    LDToolbarStop: @[LDLocalized(@"Stop"), LDLocalized(@"Stop scanning"), @"process-stop-symbolic", NSStringFromSelector(@selector(stopScan:))],
    LDToolbarSuspend: @[LDLocalized(@"Suspend"), LDLocalized(@"Suspend or resume the scan"), @"media-playback-pause-symbolic", NSStringFromSelector(@selector(toggleSuspend:))],
    LDToolbarSearch: @[LDLocalized(@"Search"), LDLocalized(@"Search for files by name"), @"system-search-symbolic", NSStringFromSelector(@selector(search:))],
    LDToolbarTrash: @[LDLocalized(@"Move to Trash"), LDLocalized(@"Move the selection to the trash"), @"user-trash-symbolic", NSStringFromSelector(@selector(moveToTrash:))],
    LDToolbarSelectParent: @[LDLocalized(@"Select Parent"), LDLocalized(@"Select the parent folder"), @"go-up-symbolic", NSStringFromSelector(@selector(selectParent:))],
    LDToolbarZoomOut: @[LDLocalized(@"Zoom Out"), LDLocalized(@"Zoom the treemap out"), @"zoom-out-symbolic", NSStringFromSelector(@selector(zoomOut:))],
    LDToolbarZoomIn: @[LDLocalized(@"Zoom In"), LDLocalized(@"Zoom the treemap into the selection"), @"zoom-in-symbolic", NSStringFromSelector(@selector(zoomIn:))],
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
                                             label:suspended ? LDLocalized(@"Resume") : LDLocalized(@"Suspend")]];
    [item setToolTip:suspended ? LDLocalized(@"Resume the scan") : LDLocalized(@"Suspend the scan")];
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
  NSTableColumn *name = [self addColumn:@"name" title:LDLocalized(@"Name") width:220 right:NO toTable:_directoryTable];
  LDIconTextCell *nameCell = [[LDIconTextCell alloc] initTextCell:@""];
  [nameCell setLineBreakMode:NSLineBreakByTruncatingTail];
  [name setDataCell:nameCell];
  [name setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
  [_directoryTable setOutlineTableColumn:name];
  [self setSortPrototypeForColumn:name ascending:YES];

  NSTableColumn *subtree = [self addColumn:@"subtree" title:LDLocalized(@"Size Proportion") width:130 right:NO toTable:_directoryTable];
  [subtree setDataCell:[[LDPercentageBarCell alloc] init]];
  [self setSortPrototypeForColumn:subtree ascending:NO];

  // WinDirStat's optional columns, shown per Preferences > Folder List or
  // the header's column chooser.
  NSDictionary *specs = @{
    LDColumnPercentage: @[LDLocalized(@"Percentage"), @105, @YES],
    LDColumnPhysicalSize: @[LDLocalized(@"Physical Size"), @90, @YES],
    LDColumnLogicalSize: @[LDLocalized(@"Logical Size"), @90, @YES],
    LDColumnItems: @[LDLocalized(@"Items"), @70, @YES],
    LDColumnFiles: @[LDLocalized(@"Files"), @70, @YES],
    LDColumnFolders: @[LDLocalized(@"Folders"), @70, @YES],
    LDColumnLastChange: @[LDLocalized(@"Last Change"), @140, @NO],
    LDColumnAttributes: @[LDLocalized(@"Attributes"), @80, @NO],
    LDColumnOwner: @[LDLocalized(@"Owner"), @110, @NO],
  };
  for (NSString *identifier in [LDPreferences optionalColumns]) {
    NSArray *spec = [specs objectForKey:identifier];
    NSTableColumn *column = [self addColumn:identifier
                                      title:[spec objectAtIndex:0]
                                      width:[[spec objectAtIndex:1] doubleValue]
                                      right:[[spec objectAtIndex:2] boolValue]
                                    toTable:_directoryTable];
    if (![identifier isEqualToString:LDColumnAttributes] && ![identifier isEqualToString:LDColumnOwner]) {
      BOOL ascending = [identifier isEqualToString:LDColumnLastChange];
      [self setSortPrototypeForColumn:column ascending:ascending];
    }
  }

  // Before the saved layout is restored: the chooser keeps this order.
  __weak AppController *weakSelf = self;
  [self addColumnChooserForTable:_directoryTable list:LDColumnListFolders required:@[@"name", @"subtree"] changed:^{
    [weakSelf fitFlexibleColumns];
    [weakSelf reloadTreeKeepingSelection];
  }];

  [name setMinWidth:160.0];
  [_directoryTable setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  [_directoryTable setAllowsMultipleSelection:YES];
  // Header clicks sort; GTK never selects (and tints) a whole column.
  [_directoryTable setAllowsColumnSelection:NO];
  [_directoryTable setAutosaveName:@"LinDirStatDirectoryTree3"];
  [_directoryTable setAutosaveTableColumns:YES];
  [_directoryTable setDataSource:self];
  [_directoryTable setDelegate:self];
  // FileTreeView.cpp sorts by Size Proportion, which cannot be hidden.
  [_directoryTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"subtree" ascending:NO]]];
}

// WinDirStat 2.6's header menu for a list, made once the list's columns are
// added and before its saved layout is restored (the chooser keeps the
// columns' first order). A list that loses or regains a column refits its
// flexible column (and does whatever else changed asks).
- (LDColumnChooser *)addColumnChooserForTable:(NSTableView *)table
                                         list:(NSString *)list
                                     required:(NSArray *)required
                                      changed:(void (^)(void))changed
{
  LDColumnChooser *chooser = [[LDColumnChooser alloc] initWithTable:table
                                                               list:list
                                                    requiredColumns:required
                                                        preferences:[LDPreferences sharedPreferences]];
  __weak AppController *weakSelf = self;
  [chooser setChangeHandler:^{
    if (changed) {
      changed();
    } else {
      [weakSelf fitFlexibleColumns];
    }
  }];
  [chooser applyPreferences];
  if (!_columnChoosers) {
    _columnChoosers = [[NSMutableArray alloc] init];
  }
  [_columnChoosers addObject:chooser];
  return chooser;
}

// Applies settings that change how things look (Preferences window). Any
// preference change gets here; the lists keep their selection (GNUstep's
// tables drop it when they reload, which some of the setters below do).
- (void)applyDisplayPreferences
{
  NSArray *treeSelection = [self selectedTreeItems];
  NSInteger extensionRow = [_extensionTable selectedRow];
  id extensionSelection = extensionRow >= 0 && extensionRow < (NSInteger)[_extensionRows count]
    ? [_extensionRows objectAtIndex:(NSUInteger)extensionRow] : nil;
  // Selections dropped by reloads are not the user's: the treemap keeps its
  // selection and highlight.
  BOOL syncing = _syncingSelection;
  _syncingSelection = YES;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [LDSizeFormatter setHumanReadable:[preferences humanFormat]];
  for (NSTableView *table in @[_directoryTable, _extensionTable]) {
    [table setUsesAlternatingRowBackgroundColors:[preferences listStripes]];
    [table setGridStyleMask:[preferences listGrid] ? (NSTableViewSolidVerticalGridLineMask | NSTableViewSolidHorizontalGridLineMask) : NSTableViewGridNone];
    [table setNeedsDisplay:YES];
  }
  // The choosers also follow the preferences on their own; whichever comes
  // first, the columns change while the selection is kept here.
  for (LDColumnChooser *chooser in _columnChoosers) {
    [chooser applyPreferences];
  }
  if (_mainSplit) {
    [self applyPaneVisibility];
    [self applyChromeVisibility];
  }

  LDTreemapOptions options = [preferences treemapOptions];
  LDTreemapOptions current = [_treemapView options];
  if (memcmp(&options, &current, sizeof(options)) != 0) {
    [_treemapView setOptions:options];
    [_swatchCache removeAllObjects];
    [_extensionTable setNeedsDisplay:YES];
  }
  [_treemapView setHighlightColor:[preferences treemapHighlightColor]];
  [_directoryTable reloadData];
  [_extensionTable reloadData];
  [self selectTreeNodes:treeSelection];
  NSUInteger extensionIndex = extensionSelection ? [_extensionRows indexOfObjectIdenticalTo:extensionSelection] : NSNotFound;
  if (extensionIndex != NSNotFound) {
    [_extensionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:extensionIndex] byExtendingSelection:NO];
  } else {
    [_extensionTable deselectAll:nil];
  }
  _syncingSelection = syncing;
  [self updateSelectionField];
}

- (void)showPreferences:(id)sender
{
  (void)sender;
  [[LDOptionsWindowController sharedController] showWindow:nil];
}

- (void)buildExtensionTable
{
  _extensionTable = [[LDTableView alloc] initWithFrame:NSMakeRect(0, 0, 360, 300)];
  [(LDTableView *)_extensionTable setCommandTarget:self];
  // WinDirStat's columns; only the description gives or takes width.
  NSTableColumn *extension = [self addColumn:@"extension" title:LDLocalized(@"Extension") width:84 right:NO toTable:_extensionTable];
  [[extension dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [self setSortPrototypeForColumn:extension ascending:YES];
  NSTableColumn *color = [self addColumn:@"color" title:LDLocalized(@"Color") width:50 right:NO toTable:_extensionTable];
  [color setDataCell:[[NSImageCell alloc] initImageCell:nil]];
  NSTableColumn *description = [self addColumn:@"description" title:LDLocalized(@"Description") width:120 right:NO toTable:_extensionTable];
  [[description dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [self setSortPrototypeForColumn:description ascending:YES];
  NSTableColumn *bytes = [self addColumn:@"bytes" title:LDLocalized(@"Bytes") width:80 right:YES toTable:_extensionTable];
  [self setSortPrototypeForColumn:bytes ascending:NO];
  NSTableColumn *percent = [self addColumn:@"percent" title:LDLocalized(@"% Bytes") width:80 right:YES toTable:_extensionTable];
  [self setSortPrototypeForColumn:percent ascending:NO];
  NSTableColumn *files = [self addColumn:@"files" title:LDLocalized(@"Files") width:72 right:YES toTable:_extensionTable];
  [self setSortPrototypeForColumn:files ascending:NO];
  // GNUstep's autoresizing styles shrink every column; the description is
  // fitted by hand instead (-fitExtensionDescriptionColumn).
  [description setMinWidth:60.0];
  [self addColumnChooserForTable:_extensionTable list:LDColumnListExtensions required:nil changed:nil];
  [_extensionTable setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];

  [_extensionTable setAllowsMultipleSelection:NO];
  [_extensionTable setAllowsColumnSelection:NO];
  // WinDirStat 2.8 (0cdff4c3): a double-click searches for the extension.
  [_extensionTable setTarget:self];
  [_extensionTable setDoubleAction:@selector(extensionListDoubleClicked:)];
  [_extensionTable setAutosaveName:@"LinDirStatExtensionList3"];
  [_extensionTable setAutosaveTableColumns:YES];
  [_extensionTable setDataSource:self];
  [_extensionTable setDelegate:self];
  [_extensionTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"bytes" ascending:NO]]];
}

- (void)buildStatusBarInView:(NSView *)content
{
  NSRect bounds = [content bounds];
  _statusSeparator = [[NSBox alloc] initWithFrame:NSMakeRect(0, LDStatusBarHeight, bounds.size.width, 1)];
  [_statusSeparator setBoxType:NSBoxSeparator];
  [_statusSeparator setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [content addSubview:_statusSeparator];

  _spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12, 7, 16, 16)];
  [_spinner setStyle:NSProgressIndicatorSpinningStyle];
  [_spinner setDisplayedWhenStopped:NO];
  [_spinner setIndeterminate:YES];
  [_spinner setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
  [content addSubview:_spinner];

  // WinDirStat's status-bar progress for scans of volumes.
  _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12, 7, LDProgressBarWidth, 16)];
  [_progressBar setStyle:NSProgressIndicatorBarStyle];
  [_progressBar setIndeterminate:NO];
  [_progressBar setMinValue:0.0];
  [_progressBar setMaxValue:100.0];
  [_progressBar setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
  [_progressBar setHidden:YES];
  [content addSubview:_progressBar];

  CGFloat selectionWidth = 190.0;
  _memoryField = [self statusLabel];
  // Wide enough for the label in any language with a four-digit size.
  NSString *widest = [NSString stringWithFormat:LDLocalized(@"Memory: %@"), @"9999.9 MB"];
  CGFloat memoryWidth = MAX(130.0, ceil([widest sizeWithAttributes:@{NSFontAttributeName: [_memoryField font]}].width) + 8.0);
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
  [_statusField setStringValue:LDLocalized(@"Ready")];
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
      [flexible setMinWidth:MAX([flexible minWidth], 80.0)];
      [table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
      [LDPlatformUI configureTable:table];
    }
    // The autoresizing style keeps the fit while the window is resized; the
    // pane can also start or become narrower than the columns, so the
    // flexible column is fitted to it below as well.
  } else {
    // GNUstep also resizes the last column whenever the pane or its scroller
    // changes (-setColumnAutoresizingStyle: is not implemented), which would
    // starve the flexible column or the last one; the last column keeps its
    // natural width.
    NSTableColumn *last = [[table tableColumns] lastObject];
    NSNumber *natural = [_naturalColumnWidths objectForKey:last];
    if (last != flexible && natural && [last width] != [natural doubleValue]) {
      [last setWidth:[natural doubleValue]];
    }
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
  if ([LDPlatformUI tablesAutoresizeColumns] && [table numberOfColumns] > 0) {
    // AppKit's table styles pad the edges, and a legacy vertical scroller
    // takes width the content size still counts: fit to what is visible.
    CGFloat visible = NSWidth([[[table enclosingScrollView] contentView] bounds]);
    CGFloat overflow = NSMaxX([table rectOfColumn:[table numberOfColumns] - 1]) - visible;
    if (overflow > 0.0) {
      [flexible setWidth:MAX([flexible minWidth], [flexible width] - ceil(overflow))];
    }
  }
}

// The title's width, plus the sort indicator beside it when the table is
// sorted by this column: a header's cell size leaves the indicator out, so
// the sorted column ("Percentage", by default) would be cut to "Perce…".
- (CGFloat)headerWidthOfColumn:(NSTableColumn *)column inTable:(NSTableView *)table
{
  NSTableHeaderCell *header = (NSTableHeaderCell *)[column headerCell];
  CGFloat width = [header cellSize].width;
  NSString *sortKey = [[[table sortDescriptors] firstObject] key];
  if (sortKey && [sortKey isEqualToString:[[column sortDescriptorPrototype] key]]) {
    width += NSWidth([header sortIndicatorRectForBounds:NSMakeRect(0, 0, width, 24)]) + 6.0;
  }
  return ceil(width);
}

// WinDirStat's "Automatically resize columns": the tree's columns other
// than Name and the graph are fitted to their header and widest value among
// the rows shown (up to LDColumnFitRowLimit); Name keeps taking the rest.
- (void)fitColumnsToContents
{
  if (![[LDPreferences sharedPreferences] automaticallyResizeColumns]) {
    return;
  }
  NSInteger rows = MIN([_directoryTable numberOfRows], LDColumnFitRowLimit);
  for (NSTableColumn *column in [_directoryTable tableColumns]) {
    NSString *identifier = [column identifier];
    if ([identifier isEqualToString:@"name"] || [identifier isEqualToString:@"subtree"]) {
      continue;
    }
    NSDictionary *attributes = @{NSFontAttributeName: [[column dataCell] font] ?: [NSFont systemFontOfSize:0]};
    CGFloat widest = [self headerWidthOfColumn:column inTable:_directoryTable];
    for (NSInteger row = 0; row < rows; row++) {
      id value = [self outlineView:_directoryTable objectValueForTableColumn:column byItem:[_directoryTable itemAtRow:row]];
      if ([value isKindOfClass:[NSString class]]) {
        widest = MAX(widest, [value sizeWithAttributes:attributes].width + 12.0);
      }
    }
    CGFloat width = MAX([column minWidth], ceil(widest));
    [_naturalColumnWidths setObject:@(width) forKey:column];
    if ([column width] != width) {
      [column setWidth:width];
    }
  }
  [self fitFlexibleColumns];
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
  [_memoryField setStringValue:bytes ? [NSString stringWithFormat:LDLocalized(@"Memory: %@"), [LDSizeFormatter stringForBytes:bytes]] : @""];
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
  // Freeing a tree of millions of nodes takes a while; the last references
  // are dropped on a background queue (see -releaseInBackground:).
  NSArray *previous = [NSArray arrayWithObjects:_rootNode ?: (id)[NSNull null], _scanSession ?: (id)[NSNull null], nil];

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
  _scanAwaitingAdoption = YES;
  [self releaseInBackground:previous];
  previous = nil;
  [self configureScanSession:session];
  [session setResultsRequest:[self scanResultsRequest]];
  [self startProfilingScan:session];
  [session startAsyncScanPaths:scanPaths completion:^{
    // Ignore a scan that was replaced before it finished.
    if (session == _scanSession) {
      [self finishAsyncScan];
    }
  }];
  [self fileListsDidStartScan];

  _titleBase = [scanPaths count] > 1 ? LDLocalized(@"This Computer") : [self displayPath:scanPath];
  _progressRange = [LDScanProgress rangeForScanPaths:scanPaths options:[session scanOptions]];
  _pacmanResumedAt = 0.0;
  _lastLiveReload = 0.0;
  [self startBusyIndicator];
  [self updateScanProgress];
  [self updateScanStatus];
  [self refreshCommandState];
}

// What the scanning thread works out for -finishAsyncScan: the extension
// list, Largest Files and, while the treemap is shown, the treemap at its
// current size.
- (LDScanResultsRequest *)scanResultsRequest
{
  LDScanResultsRequest *request = [LDScanResultsRequest requestWithMetric:_sizeMetric
                                                         largestFileCount:[[LDPreferences sharedPreferences] largeFileCount]];
  if ([_treemapView superview]) {
    NSSize size = [_treemapView renderSize];
    [request setTreemapWidth:(int)size.width height:(int)size.height options:[_treemapView options]];
  }
  return request;
}

// LINDIRSTAT_PROFILE (LDProfiling.h): stall monitor and an automatic Stop.
- (void)startProfilingScan:(LDScanSession *)session
{
  _profileStopPressedAt = 0.0;
  if (![LDProfiling isEnabled]) {
    return;
  }
  [LDProfiling startStallMonitor];
  [LDProfiling takeLongestStall:NULL];
  [LDProfiling log:[NSString stringWithFormat:@"scan started (%lu threads)", (unsigned long)[session threadCount]]];
  NSTimeInterval stopAfter = [LDProfiling stopAfter];
  if (stopAfter > 0.0) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stopAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (session == _scanSession && [self isScanning]) {
        [self stopScan:nil];
      }
    });
  }
}

- (void)logProfileOfScanCompletion:(NSTimeInterval)started
{
  [LDProfiling logStep:@"main thread completion" since:started];
  [LDProfiling log:[NSString stringWithFormat:@"scan read %.0f ms, finalize %.0f ms, results %.0f ms (background)",
                    [_scanSession readDuration] * 1000.0, [_scanSession finishDuration] * 1000.0,
                    [_scanSession resultsDuration] * 1000.0]];
  NSTimeInterval stoppedAt = _profileStopPressedAt;
  // The next pass of the run loop draws the results.
  dispatch_async(dispatch_get_main_queue(), ^{
    if (stoppedAt > 0.0) {
      [LDProfiling logStep:@"stop to display" since:stoppedAt];
    }
    [LDProfiling logStep:@"completion to display" since:started];
    NSUInteger stalls = 0;
    NSTimeInterval longest = [LDProfiling takeLongestStall:&stalls];
    [LDProfiling log:[NSString stringWithFormat:@"main thread stalls over 100 ms during scan: %lu, longest %.0f ms",
                      (unsigned long)stalls, longest * 1000.0]];
  });
}

// objects (a tree, a scan session) are released on a background queue, so
// if these were the last references the main thread does not stall freeing
// them.
- (void)releaseInBackground:(NSArray *)objects
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    (void)[objects count];
  });
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
  [LDDialogs showFailures:@[[error localizedDescription] ?: LDLocalized(@"Invalid filter")]
                    title:LDLocalized(@"Fix the filter in Preferences › Filtering before scanning")];
  return NO;
}

// The timer animates the pacmen while anything runs. While scanning, it
// also re-sorts and reloads the growing tree a few times a second;
// completion arrives through the session's completion block.
- (void)startBusyIndicator
{
  [self updateProgressWidgets];
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
  // Scans and file operations can change what is in the trash.
  _trashMeasuredAt = 0.0;
  [self updateProgressWidgets];
  [self updateScanProgress];
  [self refreshCommandState];
  [self showSummaryStatus];
  [_directoryTable setNeedsDisplay:YES];
}

// The spinner while anything runs, or a percentage bar while a scan of
// volumes runs (WinDirStat's CreateProgress); the status text moves right of
// whichever shows.
- (void)updateProgressWidgets
{
  BOOL statusShown = [[LDPreferences sharedPreferences] showStatusBar];
  BOOL showBar = statusShown && [self isScanning] && _progressRange > 0;
  BOOL spin = statusShown && [self isBusy] && !showBar;
  [_progressBar setHidden:!showBar];
  if (spin) {
    [_spinner startAnimation:nil];
  } else {
    [_spinner stopAnimation:nil];
  }
  CGFloat left = showBar ? NSMaxX([_progressBar frame]) + 12.0 : 36.0;
  NSRect frame = [_statusField frame];
  if (NSMinX(frame) != left) {
    frame.size.width = NSMaxX(frame) - left;
    frame.origin.x = left;
    [_statusField setFrame:frame];
    [[_window contentView] setNeedsDisplayInRect:NSMakeRect(0, 0, NSMaxX(frame), LDStatusBarHeight)];
  }
}

// The progress bar's position and the window title's "NN% " or "Scanning "
// prefix (WinDirStat's UpdateProgress), cleared when the scan ends.
- (void)updateScanProgress
{
  NSString *prefix = nil;
  if ([self isScanning]) {
    unsigned long long position = [_scanSession bytesScanned];
    prefix = [LDScanProgress titlePrefixForPosition:position range:_progressRange suspended:[_scanSession isSuspended]];
    if (_progressRange > 0) {
      [_progressBar setDoubleValue:(double)[LDScanProgress percentForPosition:position range:_progressRange]];
    }
  }
  if ((prefix || _titlePrefix) && ![prefix isEqualToString:_titlePrefix]) {
    _titlePrefix = [prefix copy];
    if (_titleBase) {
      [_window setTitle:prefix ? [NSString stringWithFormat:@"%@ %@", prefix, _titleBase] : _titleBase];
    }
  }
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
    [_statusField setStringValue:LDLocalized(@"Stopping…")];
    return;
  }
  NSString *currentPath = [_scanSession currentPath];
  [_statusField setStringValue:[NSString stringWithFormat:LDLocalized(@"Scanning %@  ·  %lu files, %lu folders, %@"),
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
  [self updateScanProgress];
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

// Re-sorts the visible tree (for the latest sizes, or other columns),
// keeping the selected items selected.
- (void)reloadTreeKeepingSelection
{
  NSArray *selected = [self selectedTreeItems];
  BOOL syncing = _syncingSelection;
  _syncingSelection = YES;
  [_sortedChildrenCache removeAllObjects];
  [_directoryTable reloadData];
  [self selectTreeNodes:selected];
  _syncingSelection = syncing;
}

// The items of the tree's selected rows.
- (NSArray *)selectedTreeItems
{
  NSMutableArray *items = [NSMutableArray array];
  NSIndexSet *rows = [_directoryTable selectedRowIndexes];
  for (NSUInteger row = rows ? [rows firstIndex] : NSNotFound; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
    id item = [_directoryTable itemAtRow:(NSInteger)row];
    if (item) {
      [items addObject:item];
    }
  }
  return items;
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
  NSTimeInterval started = [LDProfiling now];
  LDFileNode *root = [_scanSession rootNode];
  _scanAwaitingAdoption = NO;
  [self finishBusyWork];
  if (!root) {
    [_statusField setStringValue:LDLocalized(@"Scan failed")];
    return;
  }

  BOOL sameRoot = (root == _rootNode);
  _rootNode = root;
  LDScanResults *results = [_scanSession results];
  if ([results rootNode] != root || [[results request] metric] != _sizeMetric) {
    results = nil;
  }
  BOOL changed = [self updateSpaceItems];
  [LDProfiling logStep:@"space items" since:started];
  [self reloadResultsWithScanResults:results treemapIsCurrent:!changed];
  [LDProfiling logStep:results ? @"reload results (scan results)" : @"reload results" since:started];
  if (!sameRoot) {
    [_directoryTable expandItem:root];
  }
  [self showSummaryStatus];
  [self updateSelectionField];
  BOOL largestAreCurrent = [[results request] largestFileCount] == [[LDPreferences sharedPreferences] largeFileCount];
  [self fileListsDidFinishScanWithLargestFiles:largestAreCurrent ? [results largestFiles] : nil];
  [LDProfiling logStep:@"file lists" since:started];
  [self fitColumnsToContents];
  if (!_loadedFile) {
    [LDPlatformUI scanDidFinishWithRoot:root window:_window];
  }
  if ([LDProfiling isEnabled]) {
    [self logProfileOfScanCompletion:started];
  }
}

- (void)showSummaryStatus
{
  if (!_rootNode) {
    [_statusField setStringValue:LDLocalized(@"Ready")];
    return;
  }
  NSString *canceled = [_scanSession state] == LDScanSessionStateCanceled ? LDLocalized(@"Scan stopped, partial results  ·  ") : @"";
  NSString *problems = @"";
  if ([_scanSession errorCount] > 0) {
    problems = [NSString stringWithFormat:LDLocalized(@", %lu unreadable"), (unsigned long)[_scanSession errorCount]];
  }
  if (_loadedFile) {
    [_statusField setStringValue:[NSString stringWithFormat:LDLocalized(@"%lu files, %lu folders, %@  ·  loaded from %@"),
                                  (unsigned long)[_rootNode fileCount],
                                  (unsigned long)MAX((NSUInteger)1, [_rootNode directoryCount]) - 1,
                                  [LDSizeFormatter stringForBytes:[_rootNode aggregateSizeForMetric:_sizeMetric]],
                                  [self displayPath:_loadedFile]]];
    return;
  }
  [_statusField setStringValue:[NSString stringWithFormat:LDLocalized(@"%@%lu files, %lu folders, %@%@ in %.1f s"),
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
  [self reloadResultsWithScanResults:nil treemapIsCurrent:NO];
}

// As -reloadResults, taking what results (worked out by the scan for
// _rootNode) has; its treemap only if the tree did not change since.
- (void)reloadResultsWithScanResults:(LDScanResults *)results treemapIsCurrent:(BOOL)treemapIsCurrent
{
  [_sortedChildrenCache removeAllObjects];
  [_ownerCache removeAllObjects];
  NSArray *stats = results ? [results extensionStats] : [LDExtensionStats sortedStatsForRootNode:_rootNode metric:_sizeMetric];
  NSDictionary *colorIndexes = [results colorIndexes];
  NSData *pixels = [results treemapPixels];
  NSSet *grouped = [self unregisteredExtensionKeysInStats:stats];
  if ([grouped count] > 0) {
    // The grouped types share one colour, so the treemap is drawn again.
    [LDExtensionStats assignColorsToSortedStats:stats metric:_sizeMetric grouping:grouped];
    colorIndexes = nil;
    pixels = nil;
  }
  if (!colorIndexes) {
    colorIndexes = [LDExtensionStats colorIndexMapForSortedStats:stats];
  }
  _extensionRows = [self sortedExtensionRows:[LDExtensionStats rowsForStats:stats grouping:grouped]];
  _syncingSelection = YES;
  [_directoryTable deselectAll:nil];
  [_extensionTable deselectAll:nil];
  _syncingSelection = NO;
  [_treemapView setHighlightedExtensionKey:nil];
  [_treemapView setRootNode:_rootNode
                     metric:_sizeMetric
               colorIndexes:colorIndexes
                    treemap:treemapIsCurrent ? [results treemap] : nil
                     pixels:pixels];
  [_directoryTable reloadData];
  [_extensionTable reloadData];
  [self fitFlexibleColumns];
}

// With Group Unregistered Types on: the extensions in stats that have no
// registered type.
- (NSSet *)unregisteredExtensionKeysInStats:(NSArray *)stats
{
  if (![[LDPreferences sharedPreferences] groupUnregisteredTypes]) {
    return [NSSet set];
  }
  LDFileTypeDescriptions *descriptions = [LDFileTypeDescriptions sharedDescriptions];
  NSMutableSet *keys = [NSMutableSet set];
  for (LDExtensionStats *entry in stats) {
    if (![descriptions isExtensionKeyRegistered:[entry extensionKey]]) {
      [keys addObject:[entry extensionKey]];
    }
  }
  return keys;
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
  BOOL syncing = _syncingSelection;
  _syncingSelection = YES;
  NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
  for (LDFileNode *node in nodes) {
    NSInteger row = [_rootNode isAncestorOf:node] ? [_directoryTable rowForItem:node] : -1;
    if (row >= 0) {
      [rows addIndex:(NSUInteger)row];
    }
  }
  [_directoryTable selectRowIndexes:rows byExtendingSelection:NO];
  _syncingSelection = syncing;
}

- (void)forgetNode:(LDFileNode *)node replacement:(LDFileNode *)replacement
{
  // The outline view still shows node (it has left the tree already).
  BOOL wasExpanded = [_directoryTable isItemExpanded:node];
  NSArray *expanded = wasExpanded ? [self expandedNamePathsBelow:node] : @[];
  NSMutableArray *selected = [[self selectedTreeItems] mutableCopy];
  BOOL wasSelected = [selected indexOfObjectIdenticalTo:node] != NSNotFound
    || [[self listedSelectedNodes] indexOfObjectIdenticalTo:node] != NSNotFound;
  BOOL syncing = _syncingSelection;
  _syncingSelection = YES;
  [_directoryTable collapseItem:node collapseChildren:YES];
  [_sortedChildrenCache removeAllObjects];
  [_directoryTable reloadData];
  // Like WinDirStat, which refreshes items in place: the folders that were
  // open stay open.
  if (replacement && wasExpanded) {
    [_directoryTable expandItem:replacement];
    for (NSArray *names in expanded) {
      LDFileNode *folder = [self nodeBelow:replacement alongNames:names];
      if (folder) {
        [_directoryTable expandItem:folder];
      }
    }
  }
  if (replacement && wasSelected) {
    [selected addObject:replacement];
    [_treemapView setSelectedNode:replacement];
  }
  [self selectTreeNodes:selected];
  _syncingSelection = syncing;
}

// The name paths (relative to node) of the expanded folders below it.
- (NSArray *)expandedNamePathsBelow:(LDFileNode *)node
{
  NSMutableArray *paths = [NSMutableArray array];
  NSInteger count = [_directoryTable numberOfRows];
  for (NSInteger row = [_directoryTable rowForItem:node] + 1; row > 0 && row < count; row++) {
    LDFileNode *item = [_directoryTable itemAtRow:row];
    if (![node isAncestorOf:item]) {
      break;
    }
    if (![_directoryTable isItemExpanded:item]) {
      continue;
    }
    NSMutableArray *names = [NSMutableArray array];
    for (LDFileNode *cursor = item; cursor && cursor != node; cursor = [cursor parent]) {
      const char *name = [cursor nameBytes];
      [names insertObject:[NSData dataWithBytes:name length:strlen(name)] atIndex:0];
    }
    [paths addObject:names];
  }
  return paths;
}

- (LDFileNode *)nodeBelow:(LDFileNode *)node alongNames:(NSArray *)names
{
  LDFileNode *cursor = node;
  for (NSData *name in names) {
    LDFileNode *next = nil;
    for (LDFileNode *child in [cursor children]) {
      const char *bytes = [child nameBytes];
      if (strlen(bytes) == [name length] && memcmp(bytes, [name bytes], [name length]) == 0) {
        next = child;
        break;
      }
    }
    cursor = next;
    if (!cursor) {
      return nil;
    }
  }
  return cursor;
}

- (void)showLoadedTree:(LDFileNode *)root fromFile:(NSString *)path
{
  [_scanSession cancel];
  _scanSession = nil;
  _scanAwaitingAdoption = NO;
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
  _titleBase = [NSString stringWithFormat:@"%@ (%@)", [self displayPath:[root path]], [path lastPathComponent]];
  _titlePrefix = nil;
  [_window setTitle:_titleBase];
  [self showSummaryStatus];
  [self refreshCommandState];
  [self fileListsDidFinishScanWithLargestFiles:nil];
  [self fitColumnsToContents];
}

- (void)suspendScan:(id)sender
{
  (void)sender;
  [_scanSession suspend];
  [self showStatus:LDLocalized(@"Scan suspended")];
  [self updateScanProgress];
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
  _pacmanResumedAt = [self pacmanTime];
  [self updateScanProgress];
  [self refreshCommandState];
}

// WinDirStat 2.6 (5e3dcd0e): changed filtering settings stop the scan and
// refresh everything. Results loaded from a file are left as they are.
- (void)filtersDidChange:(NSNotification *)notification
{
  (void)notification;
  if (!_rootNode || _loadedFile) {
    return;
  }
  [self stopScan:nil];
  [self rescan:nil];
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
  if ([self isScanning]) {
    _profileStopPressedAt = [LDProfiling now];
  }
  [_scanSession cancel];
  [_refreshSession cancel];
  [_refreshQueue removeAllObjects];
  [self stopDuplicateDetection];
  if ([self isBusy]) {
    [_statusField setStringValue:LDLocalized(@"Stopping…")];
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

// WinDirStat's OnViewAbsolutePercentages: only the Percentage column changes;
// siblings keep their order, so the tree is not re-sorted.
- (void)toggleAbsolutePercentages:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setUseAbsolutePercentages:![preferences useAbsolutePercentages]];
  [_directoryTable setNeedsDisplay:YES];
}

- (void)toggleGrid:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setTreemapGrid:![preferences treemapGrid]];
}

// WinDirStat 2.6's OnViewShowFolderFramesOnTreeMap.
- (void)toggleFolderFrames:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setTreemapShowFolderFrames:![preferences treemapShowFolderFrames]];
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

// WinDirStat's first status pane for a selection: one item's path, or for
// several "N Items Selected | N Files | N Folders" (WinDirStat 2.6, 9e134e2d).
- (NSString *)statusForSelection:(NSArray *)nodes
{
  if ([nodes count] < 2) {
    return [nodes count] ? [self describeNode:[nodes lastObject]] : nil;
  }
  NSUInteger files = 0;
  NSUInteger folders = 0;
  [LDCommandRules countFiles:&files folders:&folders inNodes:nodes];
  return [NSString stringWithFormat:LDLocalized(@"%lu Items Selected | %lu Files | %lu Folders"),
          (unsigned long)[nodes count], (unsigned long)files, (unsigned long)folders];
}

// WinDirStat's second status pane: the size of everything selected. Empty
// while an extension is the selection, as WinDirStat leaves it while its
// extension list has focus: the tree's selection is no longer what the
// status bar describes.
- (void)updateSelectionField
{
  unsigned long long total = 0;
  NSArray *nodes = [_treemapView highlightedExtensionKey] ? @[] : [LDCommandRules topmostNodes:[self selectedNodes]];
  for (LDFileNode *node in nodes) {
    total += [node aggregateSizeForMetric:_sizeMetric];
  }
  NSString *label = _sizeMetric == LDSizeMetricLogical ? LDLocalized(@"Logical Size") : LDLocalized(@"Physical Size");
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
  NSArray *nodes = [self selectedNodes];
  if ([nodes count] > 1) {
    [_statusField setStringValue:[self statusForSelection:nodes]];
  } else if (node) {
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
    [self updateSelectionField];
    return;
  }
  LDExtensionStats *stats = [_extensionRows objectAtIndex:row];
  // The grouped row highlights every unregistered type at once.
  if ([stats isGroup]) {
    [_treemapView setHighlightedExtensionKeys:[stats groupedKeys]];
  } else {
    [_treemapView setHighlightedExtensionKey:[stats extensionKey]];
  }
  [self updateSelectionField];
  NSString *pattern = [stats isGroup] ? LDLocalized(@"Grouped Extensions")
    : [[stats extensionKey] isEqualToString:LDLocalized(@"<none>")] ? LDLocalized(@"Files without an extension") : [@"*" stringByAppendingString:[stats displayName]];
  [_statusField setStringValue:[NSString stringWithFormat:LDLocalized(@"%@  ·  %lu files, %@"),
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
  // Size, Size Proportion and Percentage sort by the size the treemap uses.
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
  // The sort indicator moved to another column, which may need the room.
  [self fitColumnsToContents];
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
    NSImage *source = [LDPlatformUI symbolicImageNamed:name];
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
    if ([stats isGroup]) {
      return LDLocalized(@"Grouped Extensions");
    }
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

// A node's share of its parent, as the Size Proportion bar shows it.
- (double)fractionOfParentForNode:(LDFileNode *)node
{
  return [node fractionOfParentForMetric:_sizeMetric];
}

// WinDirStat 2.6's Size Proportion tooltip (IDS_SIZE_PROPORTION_TOOLTIPss).
- (NSString *)sizeProportionToolTipForNode:(LDFileNode *)node
{
  return [NSString stringWithFormat:LDLocalized(@"Size proportion of total scan: %.1f%%\nSize proportion of parent folder: %.1f%%"),
                   [node fractionOfRootForMetric:_sizeMetric] * 100.0, [self fractionOfParentForNode:node] * 100.0];
}

- (NSString *)listView:(NSTableView *)view toolTipAtRow:(NSInteger)row column:(NSInteger)column
{
  if (view != (NSTableView *)_directoryTable || column >= (NSInteger)[[view tableColumns] count]
      || ![[[[view tableColumns] objectAtIndex:(NSUInteger)column] identifier] isEqualToString:@"subtree"]) {
    return nil;
  }
  LDFileNode *node = [_directoryTable itemAtRow:row];
  return node && ![node isScanPending] ? [self sizeProportionToolTipForNode:node] : nil;
}

// The Percentage column: the share of the whole scan, or of the parent with
// Show Absolute Percentages off (WinDirStat's GetText, COL_PERCENTAGE).
- (double)percentageFractionForNode:(LDFileNode *)node
{
  return [[LDPreferences sharedPreferences] useAbsolutePercentages]
    ? [node fractionOfRootForMetric:_sizeMetric]
    : [node fractionOfParentForMetric:_sizeMetric];
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
    // WinDirStat's time spent: the root's, and that of every row whose
    // folder is still being read (IX GetText, MustShowReadJobs).
    if ([self isScanning] && [[LDPreferences sharedPreferences] showTimeSpent]) {
      if (node == _rootNode) {
        return [NSString stringWithFormat:@"[%@]", LDFormatScanDuration((NSUInteger)[_scanSession elapsedTime])];
      }
      if ([[node parent] isScanPending]) {
        return [NSString stringWithFormat:@"[%@]", LDFormatScanDuration([node scanSecondsAt:LDScanClockActiveMilliseconds()])];
      }
    }
    return [self percentStringForFraction:[self percentageFractionForNode:node]];
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
    [bar setFraction:[self fractionOfParentForNode:node]
        absoluteFraction:[node fractionOfRootForMetric:_sizeMetric]
                   depth:[node depth]];
    BOOL pending = [node isScanPending];
    BOOL animate = [[LDPreferences sharedPreferences] pacmanAnimation];
    NSTimeInterval time = [self pacmanTime];
    BOOL asleep = NO;
    if (pending && animate) {
      uint64_t idle = [node millisecondsSinceScanActivityAt:LDScanClockMilliseconds()];
      asleep = LDPacmanIsAsleep(idle, (uint64_t)(MAX(0.0, time - _pacmanResumedAt) * 1000.0),
                                [self isScanning] && [_scanSession isSuspended]);
      if (asleep) {
        // A sleeping pacman stays where it stopped.
        time = MAX(0.0, time - idle / 1000.0);
      }
    }
    [bar setShowsPacman:pending && animate time:time asleep:asleep];
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
