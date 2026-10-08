#import "AppController.h"
#import "LDExtensionColor.h"
#import "LDExtensionStats.h"
#import "LDFileNode.h"
#import "LDFileTypeDescriptions.h"
#import "LDScanSession.h"
#import "LDSizeFormatter.h"
#import "LDSystemInfo.h"
#import "LDTreeCells.h"
#import "LDTreemapLayout.h"
#import "LDTreemapView.h"
#import "GSOpenSave.h"

#include <sys/stat.h>

static NSString *const LDToolbarSelectTarget = @"SelectTarget";
static NSString *const LDToolbarRefresh = @"Refresh";
static NSString *const LDToolbarStop = @"Stop";
static NSString *const LDToolbarSelectParent = @"SelectParent";
static NSString *const LDToolbarZoomIn = @"ZoomIn";
static NSString *const LDToolbarZoomOut = @"ZoomOut";

static const CGFloat LDStatusBarHeight = 30.0;

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

  _sizeMetric = LDSizeMetricPhysical;
  _treeSortKey = LDTreeSortKeyPhysicalSize;
  _treeSortAscending = NO;
  _treeSortIsDefault = YES;
  _swatchCache = [[NSMutableDictionary alloc] init];
  _tintedIcons = [[NSMutableDictionary alloc] init];
  _sortedChildrenCache = [NSMapTable strongToStrongObjectsMapTable];
  _dateFormatter = [[NSDateFormatter alloc] init];
  [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
  GSOpenSaveSetMode(GSOpenSaveModeAuto);

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
  [self beginScanPath:[self initialScanPath]];
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

- (void)buildMainMenu
{
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"LinDirStat"];

  NSMenu *appMenu = [self addSubmenuTitled:@"LinDirStat" to:mainMenu];
  [self addItemTo:appMenu title:@"About LinDirStat" action:@selector(orderFrontStandardAboutPanel:) key:nil target:NSApp];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:appMenu title:@"Quit" action:@selector(terminate:) key:@"q" target:NSApp];

  NSMenu *fileMenu = [self addSubmenuTitled:@"File" to:mainMenu];
  [self addItemTo:fileMenu title:@"Select Target…" action:@selector(openPath:) key:@"o" target:self];
  [self addItemTo:fileMenu title:@"Refresh All" action:@selector(rescan:) key:@"r" target:self];
  [self addItemTo:fileMenu title:@"Stop Scan" action:@selector(stopScan:) key:@"." target:self];

  NSMenu *editMenu = [self addSubmenuTitled:@"Edit" to:mainMenu];
  [self addItemTo:editMenu title:@"Copy Path" action:@selector(copyPath:) key:@"c" target:self];

  NSMenu *treemapMenu = [self addSubmenuTitled:@"Treemap" to:mainMenu];
  [self addItemTo:treemapMenu title:@"Zoom In" action:@selector(zoomIn:) key:@"+" target:self];
  [self addItemTo:treemapMenu title:@"Zoom Out" action:@selector(zoomOut:) key:@"-" target:self];
  [self addItemTo:treemapMenu title:@"Reset Zoom" action:@selector(resetZoom:) key:@"0" target:self];
  [self addItemTo:treemapMenu title:@"Select Parent" action:@selector(selectParent:) key:nil target:self];
  [treemapMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:treemapMenu title:@"Use Logical Size" action:@selector(toggleLogicalSize:) key:@"l" target:self];
  [self addItemTo:treemapMenu title:@"Show Grid" action:@selector(toggleGrid:) key:nil target:self];
  [self addItemTo:treemapMenu title:@"SequoiaView Layout" action:@selector(toggleLayoutStyle:) key:nil target:self];

  [NSApp setMainMenu:mainMenu];
}

- (BOOL)isScanning
{
  return _scanSession && ![_scanSession isFinished];
}

- (BOOL)validateAction:(SEL)action
{
  if (action == @selector(zoomIn:)) {
    return [_treemapView canZoomIn];
  }
  if (action == @selector(zoomOut:) || action == @selector(resetZoom:)) {
    return [_treemapView canZoomOut];
  }
  if (action == @selector(selectParent:)) {
    return [_treemapView canSelectParent];
  }
  if (action == @selector(copyPath:)) {
    return [self selectedNode] != nil;
  }
  if (action == @selector(stopScan:)) {
    return [self isScanning];
  }
  if (action == @selector(toggleLogicalSize:) || action == @selector(openPath:) || action == @selector(rescan:)) {
    return ![self isScanning];
  }
  return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = [item action];
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
  return @[LDToolbarSelectTarget, LDToolbarRefresh, LDToolbarStop,
           NSToolbarFlexibleSpaceItemIdentifier,
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
  [item setImage:[NSImage imageNamed:[spec objectAtIndex:2]]];
  [item setTarget:self];
  [item setAction:NSSelectorFromString([spec objectAtIndex:3])];
  return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
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
  _directoryTable = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 700, 300)];
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

  // One Size column that follows Use Logical Size: at GNOME's metrics
  // WinDirStat's separate physical and logical columns do not fit beside the
  // extension list.
  NSArray *numeric = @[@[@"percent", @"Percentage", @90],
                       @[@"size", @"Size", @90],
                       @[@"files", @"Files", @80]];
  for (NSArray *spec in numeric) {
    NSTableColumn *column = [self addColumn:[spec objectAtIndex:0]
                                      title:[spec objectAtIndex:1]
                                      width:[[spec objectAtIndex:2] doubleValue]
                                      right:YES
                                    toTable:_directoryTable];
    [self setSortPrototypeForColumn:column ascending:NO];
  }
  NSTableColumn *lastChange = [self addColumn:@"lastChange" title:@"Last Change" width:140 right:NO toTable:_directoryTable];
  [self setSortPrototypeForColumn:lastChange ascending:NO];

  [name setMinWidth:160.0];
  [_directoryTable setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  [_directoryTable setAllowsMultipleSelection:NO];
  // Header clicks sort; GTK never selects (and tints) a whole column.
  [_directoryTable setAllowsColumnSelection:NO];
  [_directoryTable setAutosaveName:@"LinDirStatDirectoryTree2"];
  [_directoryTable setAutosaveTableColumns:YES];
  [_directoryTable setDataSource:self];
  [_directoryTable setDelegate:self];
  [_directoryTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"size" ascending:NO]]];
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
  [_treemapView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  // WinDirStat's composition: directory tree and extension list side by
  // side above the full-width treemap.
  _topSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, bounds.size.width, 300)];
  [_topSplit setVertical:YES];
  [_topSplit setDividerStyle:NSSplitViewDividerStyleThin];
  [_topSplit setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [_topSplit addSubview:[self scrollViewWithDocumentView:_directoryTable]];
  [_topSplit addSubview:[self scrollViewWithDocumentView:_extensionTable]];
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

- (NSString *)initialScanPath
{
  NSArray *arguments = [[NSProcessInfo processInfo] arguments];
  NSUInteger i = 1;
  while (i < [arguments count]) {
    NSString *argument = [arguments objectAtIndex:i];
    if (![argument hasPrefix:@"-"]) {
      return argument;
    }
    i += 2; // Skip a GNUstep "-Key value" default.
  }

  NSString *environmentPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"LINDIRSTAT_SCAN_PATH"];
  if ([environmentPath length] > 0) {
    return environmentPath;
  }

  return [self defaultFixturePath];
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
  if (!scanPath) {
    return;
  }

  [_scanTimer invalidate];
  _scanTimer = nil;
  _currentScanPath = [scanPath copy];

  LDScanSession *session = [[LDScanSession alloc] init];
  _scanSession = session;
  [session setSortMetric:_sizeMetric];
  [session startAsyncScanPath:scanPath completion:^{
    // Ignore a scan that was replaced before it finished.
    if (session == _scanSession) {
      [self finishAsyncScan];
    }
  }];

  [_window setTitle:[self displayPath:scanPath]];
  [_treemapView setDimmed:YES];
  [_spinner startAnimation:nil];
  [self updateScanStatus];
  [self refreshCommandState];

  // Progress only; completion arrives through the session's completion block.
  _scanTimer = [NSTimer scheduledTimerWithTimeInterval:0.15
                                                target:self
                                              selector:@selector(scanTimerFired:)
                                              userInfo:nil
                                               repeats:YES];
}

- (void)updateScanStatus
{
  NSString *currentPath = [_scanSession currentPath];
  [_statusField setStringValue:[NSString stringWithFormat:@"Scanning %@  ·  %lu files, %lu folders, %@",
                                [self displayPath:currentPath ? currentPath : _currentScanPath],
                                (unsigned long)[_scanSession filesScanned],
                                (unsigned long)[_scanSession directoriesScanned],
                                [LDSizeFormatter stringForBytes:[_scanSession bytesScanned]]]];
}

- (void)scanTimerFired:(NSTimer *)timer
{
  (void)timer;
  [self updateScanStatus];
}

- (void)finishAsyncScan
{
  [_scanTimer invalidate];
  _scanTimer = nil;
  [_spinner stopAnimation:nil];
  LDFileNode *root = [_scanSession rootNode];
  [_treemapView setDimmed:NO];
  [self refreshCommandState];
  if (!root) {
    [_statusField setStringValue:@"Scan failed"];
    return;
  }

  _rootNode = root;
  [self reloadResults];
  [_directoryTable expandItem:root];
  [self showSummaryStatus];
  [self updateSelectionField];
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
  [_statusField setStringValue:[NSString stringWithFormat:@"%@%lu files, %lu folders, %@%@ in %.1f s",
                                canceled,
                                (unsigned long)[_rootNode fileCount],
                                (unsigned long)[_rootNode directoryCount],
                                [LDSizeFormatter stringForBytes:[_rootNode aggregateSizeForMetric:_sizeMetric]],
                                problems,
                                [_scanSession elapsedTime]]];
}

// Rebuilds the extension list and treemap from _rootNode for the current metric.
- (void)reloadResults
{
  [_sortedChildrenCache removeAllObjects];
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
}

- (void)rescan:(id)sender
{
  (void)sender;
  [self beginScanPath:_currentScanPath ? _currentScanPath : [self defaultFixturePath]];
}

- (void)stopScan:(id)sender
{
  (void)sender;
  [_scanSession cancel];
  [_statusField setStringValue:@"Stopping…"];
}

- (void)openPath:(id)sender
{
  (void)sender;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setCanChooseFiles:NO];
  [panel setCanChooseDirectories:YES];
  [panel setAllowsMultipleSelection:NO];
  NSInteger result = [panel runModalForDirectory:_currentScanPath file:nil types:nil];
  if (result == NSFileHandlingPanelOKButton || result == NSOKButton) {
    [self beginScanPath:[self selectedDirectoryPathFromOpenPanel:panel]];
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

- (LDFileNode *)selectedNode
{
  return [_treemapView selectedNode];
}

- (void)copyPath:(id)sender
{
  (void)sender;
  LDFileNode *node = [self selectedNode];
  if (!node) {
    return;
  }
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
  [pasteboard declareTypes:@[NSStringPboardType] owner:nil];
  [pasteboard setString:[node path] forType:NSStringPboardType];
  [_statusField setStringValue:[NSString stringWithFormat:@"Copied %@", [self displayPath:[node path]]]];
}

- (void)toggleLogicalSize:(id)sender
{
  (void)sender;
  _sizeMetric = (_sizeMetric == LDSizeMetricLogical) ? LDSizeMetricPhysical : LDSizeMetricLogical;
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
  LDTreemapOptions options = [_treemapView options];
  options.grid = !options.grid;
  [_treemapView setOptions:options];
}

- (void)toggleLayoutStyle:(id)sender
{
  (void)sender;
  LDTreemapOptions options = [_treemapView options];
  options.style = (options.style == LDTreemapStyleKDirStat) ? LDTreemapStyleSequoiaView : LDTreemapStyleKDirStat;
  [_treemapView setOptions:options];
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

- (void)updateSelectionField
{
  LDFileNode *node = [self selectedNode];
  [_selectionField setStringValue:node ? [NSString stringWithFormat:@"Selection: %@",
                                          [LDSizeFormatter stringForBytes:[node aggregateSizeForMetric:_sizeMetric]]] : @""];
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
  if (_scanTimer) {
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
  (void)notification;
  [self directorySelectionDidChange];
}

- (void)directorySelectionDidChange
{
  if (_syncingSelection) {
    return;
  }
  NSInteger row = [_directoryTable selectedRow];
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
  if ([identifier isEqualToString:@"files"]) {
    return LDTreeSortKeyFiles;
  }
  if ([identifier isEqualToString:@"lastChange"]) {
    return LDTreeSortKeyLastChange;
  }
  // Size, Subtree Percentage and Percentage sort by the size the treemap uses.
  return _sizeMetric == LDSizeMetricLogical ? LDTreeSortKeyLogicalSize : LDTreeSortKeyPhysicalSize;
}

- (void)outlineView:(NSOutlineView *)outlineView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
  (void)oldDescriptors;
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

- (NSArray *)displayChildrenOfNode:(LDFileNode *)node
{
  NSArray *children = [node children];
  if (_treeSortIsDefault || [children count] < 2) {
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
  if ([node isMountPoint]) {
    return [self iconNamed:@"drive-harddisk-symbolic"];
  }
  switch ([node kind]) {
    case LDFileNodeKindDirectory: return [self iconNamed:@"folder-symbolic"];
    case LDFileNodeKindSymlink: return [self iconNamed:@"insert-link-symbolic"];
    default: return [self iconNamed:@"text-x-generic-symbolic"];
  }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return tableView == _extensionTable ? (NSInteger)[_extensionRows count] : 0;
}

- (NSString *)percentStringForFraction:(double)fraction
{
  return [NSString stringWithFormat:@"%.1f%%", fraction * 100.0];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
  (void)tableView;
  NSString *identifier = [tableColumn identifier];
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
  (void)outlineView;
  if (!_rootNode) {
    return 0;
  }
  if (!item) {
    return 1;
  }
  return (NSInteger)[[(LDFileNode *)item children] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
  (void)outlineView;
  if (!item) {
    return _rootNode;
  }
  return [[self displayChildrenOfNode:item] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
  (void)outlineView;
  return item && [[(LDFileNode *)item children] count] > 0;
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
  (void)outlineView;
  LDFileNode *node = item;
  NSString *identifier = [tableColumn identifier];
  if ([identifier isEqualToString:@"name"]) {
    return node == _rootNode ? [self displayPath:[node path]] : [node displayName];
  }
  if ([identifier isEqualToString:@"subtree"]) {
    return nil;
  }
  if ([identifier isEqualToString:@"percent"]) {
    return [self percentStringForFraction:[self fractionOfParentForNode:node]];
  }
  if ([identifier isEqualToString:@"size"]) {
    return [LDSizeFormatter stringForBytes:[node aggregateSizeForMetric:_sizeMetric]];
  }
  if ([identifier isEqualToString:@"files"]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)[node fileCount]];
  }
  if ([identifier isEqualToString:@"lastChange"]) {
    NSTimeInterval time = [node aggregateModificationTime];
    return time > 0 ? [_dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]] : @"";
  }
  return @"";
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
  (void)outlineView;
  LDFileNode *node = item;
  NSString *identifier = [tableColumn identifier];
  if ([identifier isEqualToString:@"subtree"]) {
    [(LDPercentageBarCell *)cell setFraction:[self fractionOfParentForNode:node] depth:[node depth]];
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

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  (void)sender;
  return YES;
}

- (void)dealloc
{
  [_scanTimer invalidate];
  [_memoryTimer invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
