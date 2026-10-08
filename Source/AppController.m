#import "AppController.h"
#import "LDExtensionColor.h"
#import "LDExtensionStats.h"
#import "LDFileNode.h"
#import "LDScanSession.h"
#import "LDSizeFormatter.h"
#import "LDTreemapLayout.h"
#import "LDTreemapView.h"
#import "GSOpenSave.h"

#include <sys/stat.h>

@interface AppController (TableData) <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, LDTreemapViewDelegate>
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
  _swatchCache = [[NSMutableDictionary alloc] init];
  _dateFormatter = [[NSDateFormatter alloc] init];
  [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];

  NSRect frame = NSMakeRect(100, 100, 1100, 760);
  NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
  _window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:style
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  [_window setTitle:@"LinDirStat"];
  [_window setMinSize:NSMakeSize(760, 520)];
  GSOpenSaveSetMode(GSOpenSaveModeAuto);

  [self buildWindowContents];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(windowDidResize:)
                                               name:NSWindowDidResizeNotification
                                             object:_window];
  [self layoutWindowContents];

  [_window makeKeyAndOrderFront:nil];
  [self beginScanPath:[self initialScanPath]];
}

#pragma mark - Menus

- (NSMenuItem *)addItemTo:(NSMenu *)menu title:(NSString *)title action:(SEL)action key:(NSString *)key target:(id)target
{
  NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:title action:action keyEquivalent:key ? key : @""];
  [item setTarget:target];
  return item;
}

- (void)buildMainMenu
{
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"LinDirStat"];

  NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  [self addItemTo:fileMenu title:@"Select Target…" action:@selector(openPath:) key:@"o" target:self];
  [self addItemTo:fileMenu title:@"Refresh All" action:@selector(rescan:) key:@"r" target:self];
  [self addItemTo:fileMenu title:@"Stop Scan" action:@selector(stopScan:) key:@"." target:self];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:fileMenu title:@"Quit" action:@selector(terminate:) key:@"q" target:NSApp];
  [[mainMenu addItemWithTitle:@"File" action:NULL keyEquivalent:@""] setSubmenu:fileMenu];

  NSMenu *treemapMenu = [[NSMenu alloc] initWithTitle:@"Treemap"];
  [self addItemTo:treemapMenu title:@"Zoom In" action:@selector(zoomIn:) key:@"+" target:self];
  [self addItemTo:treemapMenu title:@"Zoom Out" action:@selector(zoomOut:) key:@"-" target:self];
  [self addItemTo:treemapMenu title:@"Reset Zoom" action:@selector(resetZoom:) key:@"0" target:self];
  [self addItemTo:treemapMenu title:@"Select Parent" action:@selector(selectParent:) key:@"" target:self];
  [treemapMenu addItem:[NSMenuItem separatorItem]];
  [self addItemTo:treemapMenu title:@"Use Logical Size" action:@selector(toggleLogicalSize:) key:@"l" target:self];
  [self addItemTo:treemapMenu title:@"Show Grid" action:@selector(toggleGrid:) key:@"" target:self];
  [self addItemTo:treemapMenu title:@"SequoiaView Layout" action:@selector(toggleLayoutStyle:) key:@"" target:self];
  [[mainMenu addItemWithTitle:@"Treemap" action:NULL keyEquivalent:@""] setSubmenu:treemapMenu];

  [NSApp setMainMenu:mainMenu];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = [item action];
  BOOL scanning = _scanSession && ![_scanSession isFinished];
  if (action == @selector(zoomIn:)) {
    return [_treemapView canZoomIn];
  }
  if (action == @selector(zoomOut:) || action == @selector(resetZoom:)) {
    return [_treemapView canZoomOut];
  }
  if (action == @selector(selectParent:)) {
    return [_treemapView canSelectParent];
  }
  if (action == @selector(toggleLogicalSize:)) {
    [item setState:_sizeMetric == LDSizeMetricLogical ? NSOnState : NSOffState];
    return !scanning;
  }
  if (action == @selector(toggleGrid:)) {
    [item setState:[_treemapView options].grid ? NSOnState : NSOffState];
    return YES;
  }
  if (action == @selector(toggleLayoutStyle:)) {
    [item setState:[_treemapView options].style == LDTreemapStyleSequoiaView ? NSOnState : NSOffState];
    return YES;
  }
  if (action == @selector(stopScan:)) {
    return scanning;
  }
  if (action == @selector(openPath:) || action == @selector(rescan:)) {
    return !scanning;
  }
  return YES;
}

#pragma mark - Window

- (void)buildWindowContents
{
  NSView *content = [_window contentView];

  _titleField = [self labelWithFrame:NSZeroRect value:@"LinDirStat"];
  [content addSubview:_titleField];

  _openButton = [self buttonWithFrame:NSZeroRect title:@"Open"];
  [_openButton setTarget:self];
  [_openButton setAction:@selector(openPath:)];
  [content addSubview:_openButton];

  _rescanButton = [self buttonWithFrame:NSZeroRect title:@"Rescan"];
  [_rescanButton setTarget:self];
  [_rescanButton setAction:@selector(rescan:)];
  [content addSubview:_rescanButton];

  _stopButton = [self buttonWithFrame:NSZeroRect title:@"Stop"];
  [_stopButton setTarget:self];
  [_stopButton setAction:@selector(stopScan:)];
  [_stopButton setEnabled:NO];
  [content addSubview:_stopButton];

  _pathField = [self labelWithFrame:NSZeroRect value:@""];
  [_pathField setAlignment:NSRightTextAlignment];
  [content addSubview:_pathField];

  _statusField = [self labelWithFrame:NSZeroRect value:@"Ready"];
  [content addSubview:_statusField];

  _directoryLabel = [self labelWithFrame:NSZeroRect value:@"Directory Tree"];
  [content addSubview:_directoryLabel];

  _directoryTable = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 560, 220)];
  NSTableColumn *nameColumn = [self addColumn:@"name" title:@"Name" width:220 toTable:_directoryTable];
  [_directoryTable setOutlineTableColumn:nameColumn];
  [self addColumn:@"subtree" title:@"Subtree Percent" width:130 toTable:_directoryTable];
  [self addColumn:@"percent" title:@"%" width:52 toTable:_directoryTable];
  [self addColumn:@"size" title:@"Size" width:84 toTable:_directoryTable];
  [self addColumn:@"files" title:@"Files" width:64 toTable:_directoryTable];
  [self addColumn:@"subdirs" title:@"Subdirs" width:64 toTable:_directoryTable];
  [self addColumn:@"lastChange" title:@"Last Change" width:130 toTable:_directoryTable];
  [self addColumn:@"attributes" title:@"Mode" width:92 toTable:_directoryTable];
  [_directoryTable setDataSource:self];
  [_directoryTable setDelegate:self];

  _directoryScroll = [self scrollViewWithFrame:NSZeroRect documentView:_directoryTable];
  [content addSubview:_directoryScroll];

  _extensionLabel = [self labelWithFrame:NSZeroRect value:@"Extension List"];
  [content addSubview:_extensionLabel];

  _extensionTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 260, 220)];
  [self addColumn:@"extension" title:@"Extension" width:84 toTable:_extensionTable];
  NSTableColumn *colorColumn = [self addColumn:@"color" title:@"Color" width:44 toTable:_extensionTable];
  [colorColumn setDataCell:[[NSImageCell alloc] initImageCell:nil]];
  [self addColumn:@"bytes" title:@"Bytes" width:72 toTable:_extensionTable];
  [self addColumn:@"percent" title:@"% Bytes" width:60 toTable:_extensionTable];
  [self addColumn:@"files" title:@"Files" width:56 toTable:_extensionTable];
  [_extensionTable setDataSource:self];
  [_extensionTable setDelegate:self];

  _extensionScroll = [self scrollViewWithFrame:NSZeroRect documentView:_extensionTable];
  [content addSubview:_extensionScroll];

  _treemapLabel = [self labelWithFrame:NSZeroRect value:@"Treemap"];
  [content addSubview:_treemapLabel];

  _treemapView = [[LDTreemapView alloc] initWithFrame:NSZeroRect];
  [_treemapView setDelegate:self];
  [content addSubview:_treemapView];
}

- (void)layoutWindowContents
{
  NSRect bounds = [[_window contentView] bounds];
  CGFloat margin = 16.0;
  CGFloat toolbarY = bounds.size.height - 44.0;
  CGFloat statusHeight = 26.0;
  CGFloat treemapHeight = MAX(170.0, floor((bounds.size.height - 116.0) * 0.48));
  CGFloat treemapY = statusHeight + 16.0;
  CGFloat treemapLabelY = treemapY + treemapHeight + 6.0;
  CGFloat tablesY = treemapLabelY + 26.0;
  CGFloat tableHeight = MAX(130.0, toolbarY - tablesY - 28.0);
  CGFloat gutter = 14.0;
  CGFloat contentWidth = bounds.size.width - (margin * 2.0);
  CGFloat leftWidth = floor((contentWidth - gutter) * 0.68);
  CGFloat rightWidth = contentWidth - gutter - leftWidth;
  CGFloat rightX = margin + leftWidth + gutter;
  CGFloat pathX = 470.0;

  [_titleField setFrame:NSMakeRect(margin, toolbarY + 4.0, 140.0, 22.0)];
  [_openButton setFrame:NSMakeRect(160.0, toolbarY, 92.0, 30.0)];
  [_rescanButton setFrame:NSMakeRect(260.0, toolbarY, 100.0, 30.0)];
  [_stopButton setFrame:NSMakeRect(368.0, toolbarY, 90.0, 30.0)];
  [_pathField setFrame:NSMakeRect(pathX, toolbarY + 4.0, MAX(80.0, bounds.size.width - pathX - margin), 22.0)];

  [_directoryLabel setFrame:NSMakeRect(margin, tablesY + tableHeight + 4.0, leftWidth, 18.0)];
  [_extensionLabel setFrame:NSMakeRect(rightX, tablesY + tableHeight + 4.0, rightWidth, 18.0)];
  [_directoryScroll setFrame:NSMakeRect(margin, tablesY, leftWidth, tableHeight)];
  [_extensionScroll setFrame:NSMakeRect(rightX, tablesY, rightWidth, tableHeight)];
  [_treemapLabel setFrame:NSMakeRect(margin, treemapLabelY, contentWidth, 18.0)];
  [_treemapView setFrame:NSMakeRect(margin, treemapY, contentWidth, treemapHeight)];
  [_statusField setFrame:NSMakeRect(margin, 10.0, contentWidth, 22.0)];
}

- (void)windowDidResize:(NSNotification *)notification
{
  (void)notification;
  [self layoutWindowContents];
}

- (NSTextField *)labelWithFrame:(NSRect)frame value:(NSString *)value
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  [label setStringValue:value];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:NO];
  return label;
}

- (NSButton *)buttonWithFrame:(NSRect)frame title:(NSString *)title
{
  NSButton *button = [[NSButton alloc] initWithFrame:frame];
  [button setTitle:title];
  [button setBezelStyle:NSRoundedBezelStyle];
  return button;
}

- (NSTableColumn *)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width toTable:(NSTableView *)table
{
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
  [[column headerCell] setStringValue:title];
  [column setWidth:width];
  [column setEditable:NO];
  [table addTableColumn:column];
  return column;
}

- (NSScrollView *)scrollViewWithFrame:(NSRect)frame documentView:(NSView *)view
{
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:YES];
  [scroll setDocumentView:view];
  return scroll;
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

- (void)updateCommandState
{
  BOOL scanning = _scanSession && ![_scanSession isFinished];
  [_stopButton setEnabled:scanning];
  [_rescanButton setEnabled:!scanning];
  [_openButton setEnabled:!scanning];
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

  [_pathField setStringValue:scanPath];
  [_window setTitle:[NSString stringWithFormat:@"Scanning — %@", [scanPath lastPathComponent]]];
  [_treemapView setDimmed:YES];
  [self updateScanStatus];
  [self updateCommandState];

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
  [_statusField setStringValue:[NSString stringWithFormat:@"Scanning… %lu files, %lu folders, %@  —  %@",
                                (unsigned long)[_scanSession filesScanned],
                                (unsigned long)[_scanSession directoriesScanned],
                                [LDSizeFormatter stringForBytes:[_scanSession bytesScanned]],
                                currentPath ? currentPath : _currentScanPath]];
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
  LDFileNode *root = [_scanSession rootNode];
  [_treemapView setDimmed:NO];
  [self updateCommandState];
  if (!root) {
    [_statusField setStringValue:@"Scan failed"];
    [_window setTitle:@"LinDirStat"];
    return;
  }

  _rootNode = root;
  [self reloadResults];
  [_directoryTable expandItem:root];
  [_window setTitle:[NSString stringWithFormat:@"%@ — LinDirStat", [root displayName]]];
  [self showSummaryStatus];
}

- (void)showSummaryStatus
{
  if (!_rootNode) {
    [_statusField setStringValue:@"Ready"];
    return;
  }
  NSString *canceled = [_scanSession state] == LDScanSessionStateCanceled ? @"Scan stopped — partial results.  " : @"";
  NSString *problems = @"";
  if ([_scanSession errorCount] > 0) {
    problems = [NSString stringWithFormat:@", %lu unreadable", (unsigned long)[_scanSession errorCount]];
  }
  [_statusField setStringValue:[NSString stringWithFormat:@"%@%lu files, %lu folders, %@%@  (%.1f s)",
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
  _extensionRows = [LDExtensionStats sortedStatsForRootNode:_rootNode metric:_sizeMetric];
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
  [_statusField setStringValue:@"Stopping scan…"];
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

#pragma mark - Treemap commands

- (void)zoomIn:(id)sender { [_treemapView zoomIn:sender]; }
- (void)zoomOut:(id)sender { [_treemapView zoomOut:sender]; }
- (void)resetZoom:(id)sender { [_treemapView resetZoom:sender]; }
- (void)selectParent:(id)sender { [_treemapView selectParent:sender]; }

- (void)toggleLogicalSize:(id)sender
{
  (void)sender;
  _sizeMetric = (_sizeMetric == LDSizeMetricLogical) ? LDSizeMetricPhysical : LDSizeMetricLogical;
  if (!_rootNode) {
    return;
  }
  LDFileNode *selected = [_treemapView selectedNode];
  [_rootNode sortChildrenByMetric:_sizeMetric];
  [self reloadResults];
  [_directoryTable expandItem:_rootNode];
  if (selected) {
    [self revealNodeInTree:selected];
    [_treemapView setSelectedNode:selected];
  }
  [self showSummaryStatus];
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
  NSEnumerator *enumerator = [ancestors objectEnumerator];
  while ((cursor = [enumerator nextObject])) {
    [_directoryTable expandItem:cursor];
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
  return [NSString stringWithFormat:@"%@  —  %@",
          [node path],
          [LDSizeFormatter stringForBytes:[node aggregateSizeForMetric:_sizeMetric]]];
}

- (void)treemapView:(LDTreemapView *)view didSelectNode:(LDFileNode *)node
{
  (void)view;
  [self revealNodeInTree:node];
  [_statusField setStringValue:[self describeNode:node]];
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
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  (void)notification;
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
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
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
  NSString *pattern = [[stats extensionKey] isEqualToString:@"<none>"] ? @"files without an extension" : [@"*" stringByAppendingString:[stats displayName]];
  [_statusField setStringValue:[NSString stringWithFormat:@"%@  —  %lu files, %@",
                                pattern,
                                (unsigned long)[stats fileCount],
                                [LDSizeFormatter stringForBytes:[stats bytesForMetric:_sizeMetric]]]];
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

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return tableView == _extensionTable ? (NSInteger)[_extensionRows count] : 0;
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
  if ([identifier isEqualToString:@"bytes"]) {
    return [LDSizeFormatter stringForBytes:[stats bytesForMetric:_sizeMetric]];
  }
  if ([identifier isEqualToString:@"percent"]) {
    return [self percentageStringForBytes:[stats bytesForMetric:_sizeMetric]];
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
  return [[(LDFileNode *)item children] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
  (void)outlineView;
  return item && [[(LDFileNode *)item children] count] > 0;
}

- (NSString *)modeStringForNode:(LDFileNode *)node
{
  unsigned int mode = [node mode];
  if (mode == 0) {
    return @"";
  }
  char text[11];
  text[0] = S_ISDIR(mode) ? 'd' : S_ISLNK(mode) ? 'l' : S_ISREG(mode) ? '-' : '?';
  const char *flags = "rwxrwxrwx";
  int i = 0;
  for (i = 0; i < 9; i++) {
    text[i + 1] = (mode & (1u << (8 - i))) ? flags[i] : '-';
  }
  text[10] = '\0';
  return [NSString stringWithUTF8String:text];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
  (void)outlineView;
  LDFileNode *node = item;
  NSString *identifier = [tableColumn identifier];
  if ([identifier isEqualToString:@"name"]) {
    return [node displayName];
  }
  if ([identifier isEqualToString:@"subtree"]) {
    return [self subtreeBarStringForNode:node];
  }
  if ([identifier isEqualToString:@"percent"]) {
    return [self percentageStringForBytes:[node aggregateSizeForMetric:_sizeMetric]];
  }
  if ([identifier isEqualToString:@"size"]) {
    return [LDSizeFormatter stringForBytes:[node aggregateSizeForMetric:_sizeMetric]];
  }
  if ([identifier isEqualToString:@"files"]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)[node fileCount]];
  }
  if ([identifier isEqualToString:@"subdirs"]) {
    NSUInteger directories = [node directoryCount];
    if ([node kind] == LDFileNodeKindDirectory && directories > 0) {
      directories--;
    }
    return [NSString stringWithFormat:@"%lu", (unsigned long)directories];
  }
  if ([identifier isEqualToString:@"lastChange"]) {
    NSTimeInterval time = [node aggregateModificationTime];
    return time > 0 ? [_dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]] : @"";
  }
  if ([identifier isEqualToString:@"attributes"]) {
    return [self modeStringForNode:node];
  }
  return @"";
}

- (NSString *)subtreeBarStringForNode:(LDFileNode *)node
{
  unsigned long long parentBytes = [[node parent] aggregateSizeForMetric:_sizeMetric];
  if (![node parent]) {
    parentBytes = [node aggregateSizeForMetric:_sizeMetric];
  }
  double percent = parentBytes == 0 ? 0.0 : ((double)[node aggregateSizeForMetric:_sizeMetric] / (double)parentBytes) * 100.0;
  NSUInteger filled = (NSUInteger)floor((percent / 100.0) * 12.0 + 0.5);
  if (filled > 12) {
    filled = 12;
  }
  NSMutableString *bar = [NSMutableString stringWithString:@"["];
  NSUInteger i = 0;
  for (i = 0; i < 12; i++) {
    [bar appendString:(i < filled) ? @"#" : @" "];
  }
  [bar appendFormat:@"] %.1f", percent];
  return bar;
}

- (NSString *)percentageStringForBytes:(unsigned long long)bytes
{
  unsigned long long total = [_rootNode aggregateSizeForMetric:_sizeMetric];
  if (total == 0) {
    return @"0.0";
  }
  return [NSString stringWithFormat:@"%.1f", ((double)bytes / (double)total) * 100.0];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  (void)sender;
  return YES;
}

- (void)dealloc
{
  [_scanTimer invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
