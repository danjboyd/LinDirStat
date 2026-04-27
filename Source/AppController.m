#import "AppController.h"
#import "LDFileNode.h"
#import "LDExtensionStats.h"
#import "LDScanSession.h"
#import "LDScanner.h"
#import "LDSizeFormatter.h"
#import "LDTreemapLayout.h"
#import "LDTreemapView.h"
#import "GSOpenSave.h"

@interface AppController (TableData) <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@implementation AppController

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  (void)notification;

  NSRect frame = NSMakeRect(100, 100, 900, 620);
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

- (void)buildWindowContents
{
  NSView *content = [_window contentView];

  _titleField = [self labelWithFrame:NSZeroRect
                                value:@"LinDirStat"];
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

  _pathField = [[self labelWithFrame:NSZeroRect value:@""] retain];
  [_pathField setAlignment:NSRightTextAlignment];
  [content addSubview:_pathField];

  _statusField = [[self labelWithFrame:NSZeroRect value:@"Ready"] retain];
  [content addSubview:_statusField];

  _directoryLabel = [[self labelWithFrame:NSZeroRect value:@"Directory Tree"] retain];
  [content addSubview:_directoryLabel];

  _directoryTable = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 560, 220)];
  NSTableColumn *nameColumn = [self addColumn:@"name" title:@"Name" width:190 toTable:_directoryTable];
  [(NSOutlineView *)_directoryTable setOutlineTableColumn:nameColumn];
  [self addColumn:@"subtree" title:@"Subtree Percent" width:130 toTable:_directoryTable];
  [self addColumn:@"percent" title:@"%" width:48 toTable:_directoryTable];
  [self addColumn:@"size" title:@"Size" width:84 toTable:_directoryTable];
  [self addColumn:@"files" title:@"Files" width:58 toTable:_directoryTable];
  [self addColumn:@"subdirs" title:@"Subdirs" width:58 toTable:_directoryTable];
  [self addColumn:@"items" title:@"Items" width:58 toTable:_directoryTable];
  [self addColumn:@"lastChange" title:@"Last Change" width:92 toTable:_directoryTable];
  [self addColumn:@"attributes" title:@"Attr" width:48 toTable:_directoryTable];
  [_directoryTable setDataSource:self];
  [_directoryTable setDelegate:self];

  _directoryScroll = [self scrollViewWithFrame:NSZeroRect documentView:_directoryTable];
  [content addSubview:_directoryScroll];

  _extensionLabel = [[self labelWithFrame:NSZeroRect value:@"Extension List"] retain];
  [content addSubview:_extensionLabel];

  _extensionTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 260, 220)];
  [self addColumn:@"extension" title:@"Ext" width:72 toTable:_extensionTable];
  [self addColumn:@"bytes" title:@"Bytes" width:90 toTable:_extensionTable];
  [self addColumn:@"percent" title:@"%" width:58 toTable:_extensionTable];
  [self addColumn:@"files" title:@"Files" width:58 toTable:_extensionTable];
  [_extensionTable setDataSource:self];
  [_extensionTable setDelegate:self];

  _extensionScroll = [self scrollViewWithFrame:NSZeroRect documentView:_extensionTable];
  [content addSubview:_extensionScroll];

  _treemapLabel = [[self labelWithFrame:NSZeroRect value:@"Treemap"] retain];
  [content addSubview:_treemapLabel];

  _treemapView = [[LDTreemapView alloc] initWithFrame:NSZeroRect];
  [content addSubview:_treemapView];
}

- (void)layoutWindowContents
{
  NSRect bounds = [[_window contentView] bounds];
  CGFloat margin = 16.0;
  CGFloat toolbarY = bounds.size.height - 82.0;
  CGFloat statusHeight = 26.0;
  CGFloat treemapHeight = MAX(170.0, floor((bounds.size.height - 116.0) * 0.43));
  CGFloat treemapY = statusHeight + 16.0;
  CGFloat treemapLabelY = treemapY + treemapHeight + 8.0;
  CGFloat tablesY = treemapLabelY + 28.0;
  CGFloat tableHeight = MAX(130.0, toolbarY - tablesY - 16.0);
  CGFloat gutter = 14.0;
  CGFloat contentWidth = bounds.size.width - (margin * 2.0);
  CGFloat leftWidth = floor((contentWidth - gutter) * 0.73);
  CGFloat rightWidth = contentWidth - gutter - leftWidth;
  CGFloat rightX = margin + leftWidth + gutter;
  CGFloat pathX = 510.0;

  [_titleField setFrame:NSMakeRect(margin, toolbarY + 4.0, 160.0, 22.0)];
  [_openButton setFrame:NSMakeRect(190.0, toolbarY, 92.0, 28.0)];
  [_rescanButton setFrame:NSMakeRect(290.0, toolbarY, 105.0, 28.0)];
  [_stopButton setFrame:NSMakeRect(403.0, toolbarY, 90.0, 28.0)];
  [_pathField setFrame:NSMakeRect(pathX, toolbarY + 4.0, MAX(80.0, bounds.size.width - pathX - margin), 22.0)];

  [_directoryLabel setFrame:NSMakeRect(margin, tablesY + tableHeight + 4.0, leftWidth, 18.0)];
  [_extensionLabel setFrame:NSMakeRect(rightX, tablesY + tableHeight + 4.0, rightWidth, 18.0)];
  [_directoryScroll setFrame:NSMakeRect(margin, tablesY, leftWidth, tableHeight)];
  [_extensionScroll setFrame:NSMakeRect(rightX, tablesY, rightWidth, tableHeight)];
  [_treemapLabel setFrame:NSMakeRect(margin, treemapLabelY, contentWidth, 18.0)];
  [_treemapView setFrame:NSMakeRect(margin, treemapY, contentWidth, treemapHeight)];
  [_statusField setFrame:NSMakeRect(margin, 10.0, contentWidth, 22.0)];

  [self updateTreemapLayout];
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
  NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:identifier] autorelease];
  [[column headerCell] setStringValue:title];
  [column setWidth:width];
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
  if ([arguments count] > 1) {
    return [arguments objectAtIndex:1];
  }

  NSString *environmentPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"LINDIRSTAT_SCAN_PATH"];
  if ([environmentPath length] > 0) {
    return environmentPath;
  }

  return [self defaultFixturePath];
}

- (void)beginScanPath:(NSString *)scanPath
{
  if (!scanPath) {
    NSLog(@"LinDirStat beginScanPath ignored nil path");
    return;
  }

  [_scanTimer invalidate];
  [_scanTimer release];
  _scanTimer = nil;

  [_currentScanPath release];
  _currentScanPath = [scanPath copy];
  _scanAnimationFrame = 0;

  [_scanSession release];
  _scanSession = [[LDScanSession alloc] init];
  [_scanSession startAsyncScanPath:scanPath];

  [_pathField setStringValue:scanPath];
  [_statusField setStringValue:[NSString stringWithFormat:@"Scanning %@...", scanPath]];
  [_stopButton setEnabled:YES];
  [_rescanButton setEnabled:NO];
  [_openButton setEnabled:NO];

  _scanTimer = [[NSTimer scheduledTimerWithTimeInterval:0.15
                                                 target:self
                                               selector:@selector(scanTimerFired:)
                                               userInfo:nil
                                                repeats:YES] retain];
}

- (void)scanTimerFired:(NSTimer *)timer
{
  (void)timer;
  static NSString *frames[] = {@"Scanning |", @"Scanning /", @"Scanning -", @"Scanning \\"};
  NSString *currentPath = [_scanSession currentPath] ? [_scanSession currentPath] : _currentScanPath;
  NSString *frame = frames[_scanAnimationFrame % 4];
  _scanAnimationFrame++;

  [_statusField setStringValue:[NSString stringWithFormat:@"%@  %@", frame, currentPath]];

  if ([_scanSession waitUntilFinishedBeforeDate:[NSDate date]]) {
    [_scanTimer invalidate];
    [_scanTimer release];
    _scanTimer = nil;
    [self finishAsyncScan];
  }
}

- (void)finishAsyncScan
{
  LDFileNode *root = [_scanSession rootNode];
  if (!root) {
    [_statusField setStringValue:@"Scan failed"];
    [_stopButton setEnabled:NO];
    [_rescanButton setEnabled:YES];
    [_openButton setEnabled:YES];
    return;
  }

  [_rootNode release];
  _rootNode = [root retain];
  _totalBytes = [root aggregateSize];

  [_directoryRows release];
  _directoryRows = nil;

  [_extensionRows release];
  _extensionRows = [[LDExtensionStats sortedStatsForRootNode:root] retain];

  [self updateTreemapLayout];

  [_directoryTable reloadData];
  [(NSOutlineView *)_directoryTable expandItem:root];
  [_extensionTable reloadData];
  [_pathField setStringValue:_currentScanPath];
  [_statusField setStringValue:[NSString stringWithFormat:@"%lu files, %lu directories, %@",
                                (unsigned long)[root fileCount],
                                (unsigned long)[root directoryCount],
                                [LDSizeFormatter stringForBytes:[root aggregateSize]]]];
  [_stopButton setEnabled:NO];
  [_rescanButton setEnabled:YES];
  [_openButton setEnabled:YES];
}

- (void)scanPath:(NSString *)scanPath
{
  if (!scanPath) {
    NSLog(@"LinDirStat scanPath ignored nil path");
    return;
  }

  NSLog(@"LinDirStat scanning path: %@", scanPath);
  [_pathField setStringValue:scanPath];
  [_statusField setStringValue:[NSString stringWithFormat:@"Scanning %@...", scanPath]];
  [_window displayIfNeeded];

  LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
  [_scanSession release];
  _scanSession = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPath:scanPath session:_scanSession];
  [_rootNode release];
  _rootNode = [root retain];
  [_currentScanPath release];
  _currentScanPath = [scanPath copy];
  _totalBytes = [root aggregateSize];

  [_directoryRows release];
  _directoryRows = nil;

  [_extensionRows release];
  _extensionRows = [[LDExtensionStats sortedStatsForRootNode:root] retain];

  [self updateTreemapLayout];

  [_directoryTable reloadData];
  [(NSOutlineView *)_directoryTable expandItem:root];
  [_extensionTable reloadData];
  [_pathField setStringValue:scanPath];
  [_statusField setStringValue:[NSString stringWithFormat:@"%lu files, %lu directories, %@",
                                (unsigned long)[root fileCount],
                                (unsigned long)[root directoryCount],
                                [LDSizeFormatter stringForBytes:[root aggregateSize]]]];
}

- (void)updateTreemapLayout
{
  if (!_rootNode || !_treemapView) {
    return;
  }
  NSArray *items = [LDTreemapLayout layoutItemsForRootNode:_rootNode inRect:[_treemapView bounds]];
  [_treemapView setItems:items];
}

- (void)rescan:(id)sender
{
  (void)sender;
  NSString *path = _currentScanPath ? _currentScanPath : [self defaultFixturePath];
  NSLog(@"LinDirStat rescan requested for path: %@", path);
  [self beginScanPath:path];
}

- (void)stopScan:(id)sender
{
  (void)sender;
  [_scanSession cancel];
  [_statusField setStringValue:@"Stopping scan..."];
}

- (void)openPath:(id)sender
{
  (void)sender;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setCanChooseFiles:NO];
  [panel setCanChooseDirectories:YES];
  [panel setAllowsMultipleSelection:NO];
  NSLog(@"LinDirStat opening directory panel from path: %@", _currentScanPath);
  NSInteger result = [panel runModalForDirectory:_currentScanPath file:nil types:nil];
  NSLog(@"LinDirStat open panel returned: %ld", (long)result);
  if (result == NSFileHandlingPanelOKButton || result == NSOKButton) {
    NSString *path = [self selectedDirectoryPathFromOpenPanel:panel];
    NSLog(@"LinDirStat selected open panel path: %@", path);
    [self beginScanPath:path];
  } else {
    [_statusField setStringValue:@"Open cancelled"];
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

- (NSArray *)flattenedRowsForNode:(LDFileNode *)node depth:(NSUInteger)depth
{
  NSMutableArray *rows = [NSMutableArray array];
  if (!node) {
    return rows;
  }
  [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                   node, @"node",
                   [NSNumber numberWithUnsignedInteger:depth], @"depth",
                   nil]];
  NSArray *children = [[node children] sortedArrayUsingSelector:@selector(compareByAggregateSizeThenName:)];
  NSEnumerator *enumerator = [children objectEnumerator];
  LDFileNode *child = nil;
  while ((child = [enumerator nextObject])) {
    [rows addObjectsFromArray:[self flattenedRowsForNode:child depth:depth + 1]];
  }
  return rows;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return tableView == _directoryTable ? 0 : [_extensionRows count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
  NSString *identifier = [tableColumn identifier];
  LDExtensionStats *stats = [_extensionRows objectAtIndex:row];
  if ([identifier isEqualToString:@"extension"]) {
    return [stats displayName];
  }
  if ([identifier isEqualToString:@"bytes"]) {
    return [LDSizeFormatter stringForBytes:[stats bytes]];
  }
  if ([identifier isEqualToString:@"percent"]) {
    return [self percentageStringForBytes:[stats bytes]];
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
  return [[[item children] sortedArrayUsingSelector:@selector(compareByAggregateSizeThenName:)] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
  (void)outlineView;
  if (!item) {
    return _rootNode;
  }
  NSArray *children = [[item children] sortedArrayUsingSelector:@selector(compareByAggregateSizeThenName:)];
  return [children objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
  (void)outlineView;
  return item && [item kind] == LDFileNodeKindDirectory && [[item children] count] > 0;
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
    return [self percentageStringForBytes:[node aggregateSize]];
  }
  if ([identifier isEqualToString:@"size"]) {
    return [LDSizeFormatter stringForBytes:[node aggregateSize]];
  }
  if ([identifier isEqualToString:@"files"]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)[node fileCount]];
  }
  if ([identifier isEqualToString:@"subdirs"]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)[node directoryCount]];
  }
  if ([identifier isEqualToString:@"items"]) {
    return [NSString stringWithFormat:@"%lu", (unsigned long)([node fileCount] + [node directoryCount])];
  }
  if ([identifier isEqualToString:@"lastChange"]) {
    NSDictionary *attributes = [[NSFileManager defaultManager] fileAttributesAtPath:[node path] traverseLink:NO];
    NSDate *date = [attributes objectForKey:NSFileModificationDate];
    return date ? [NSDateFormatter localizedStringFromDate:date
                                                 dateStyle:NSDateFormatterShortStyle
                                                 timeStyle:NSDateFormatterNoStyle] : @"";
  }
  if ([identifier isEqualToString:@"attributes"]) {
    if ([node kind] == LDFileNodeKindDirectory) {
      return @"D";
    }
    if ([node kind] == LDFileNodeKindSymlink) {
      return @"L";
    }
    if ([node kind] == LDFileNodeKindSpecial) {
      return @"S";
    }
    return @"A";
  }
  return @"";
}

- (NSString *)subtreeBarStringForNode:(LDFileNode *)node
{
  unsigned long long parentBytes = [[node parent] aggregateSize];
  if (parentBytes == 0) {
    parentBytes = _totalBytes;
  }
  double percent = parentBytes == 0 ? 0.0 : ((double)[node aggregateSize] / (double)parentBytes) * 100.0;
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
  if (_totalBytes == 0) {
    return @"0.0";
  }
  return [NSString stringWithFormat:@"%.1f", ((double)bytes / (double)_totalBytes) * 100.0];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  (void)sender;
  return YES;
}

- (void)dealloc
{
  [_window release];
  [_titleField release];
  [_openButton release];
  [_rescanButton release];
  [_stopButton release];
  [_directoryLabel release];
  [_extensionLabel release];
  [_treemapLabel release];
  [_directoryScroll release];
  [_extensionScroll release];
  [_directoryTable release];
  [_extensionTable release];
  [_statusField release];
  [_pathField release];
  [_treemapView release];
  [_directoryRows release];
  [_extensionRows release];
  [_scanTimer invalidate];
  [_scanTimer release];
  [_scanSession release];
  [_rootNode release];
  [_currentScanPath release];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

@end
