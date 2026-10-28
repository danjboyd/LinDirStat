#import "AppController.h"
#import "LDLocalization.h"
#import "AppController+Private.h"
#import "LDCSV.h"
#import "LDDialogs.h"
#import "LDDuplicateFinder.h"
#import "LDExtensionStats.h"
#import "LDFileWatcher.h"
#import "LDHasher.h"
#import "LDLargestFiles.h"
#import "LDPlatformUI.h"
#import "LDPreferences.h"
#import "LDScanSession.h"
#import "LDSearch.h"
#import "LDSizeFormatter.h"
#import "LDTreemapView.h"

static NSString *const LDTabAllFiles = @"all";
static NSString *const LDTabLargest = @"largest";
static NSString *const LDTabDuplicates = @"duplicates";
static NSString *const LDTabSearch = @"search";
static NSString *const LDTabWatcher = @"watcher";

// WinDirStat's tabbed file view (FileTabbedView.cpp): All Files, Largest
// Files, Duplicate Files (when duplicate detection is on), Search Results
// (after a search) and File Watcher (while Tools › Start File Watcher is
// on). Each list's selection drives the treemap and commands.
@implementation AppController (FileLists)

#pragma mark - Building

- (NSTableView *)fileListTable:(BOOL)outline
                     nameTitle:(NSString *)nameTitle
                  autosaveName:(NSString *)autosaveName
                    columnList:(NSString *)list
{
  NSTableView *table = outline
    ? [[LDOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 700, 300)]
    : [[LDTableView alloc] initWithFrame:NSMakeRect(0, 0, 700, 300)];
  [(id)table setCommandTarget:self];
  NSTableColumn *name = [self addColumn:@"path" title:nameTitle width:420 right:NO toTable:table];
  [[name dataCell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [name setMinWidth:160.0];
  [self setSortPrototypeForColumn:name ascending:YES];
  if (outline) {
    [(NSOutlineView *)table setOutlineTableColumn:name];
    NSTableColumn *items = [self addColumn:@"items" title:LDLocalized(@"Items") width:60 right:YES toTable:table];
    [self setSortPrototypeForColumn:items ascending:NO];
  }
  NSArray *columns = @[@[@"physicalSize", LDLocalized(@"Physical Size")], @[@"logicalSize", LDLocalized(@"Logical Size")]];
  for (NSArray *spec in columns) {
    NSTableColumn *column = [self addColumn:[spec objectAtIndex:0] title:[spec objectAtIndex:1] width:90 right:YES toTable:table];
    [self setSortPrototypeForColumn:column ascending:NO];
  }
  NSTableColumn *lastChange = [self addColumn:@"lastChange" title:LDLocalized(@"Last Change") width:140 right:NO toTable:table];
  [self setSortPrototypeForColumn:lastChange ascending:YES];
  [self addColumnChooserForTable:table list:list required:nil changed:nil];
  [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  [table setAllowsMultipleSelection:YES];
  [table setAllowsColumnSelection:NO];
  [table setAutosaveName:autosaveName];
  [table setAutosaveTableColumns:YES];
  [table setDataSource:self];
  [table setDelegate:self];
  return table;
}

- (NSTabViewItem *)tabItemWithIdentifier:(NSString *)identifier label:(NSString *)label view:(NSView *)view
{
  NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:identifier];
  [item setLabel:label];
  [item setView:view];
  return item;
}

- (NSView *)buildFileTabs
{
  _largestTable = (LDTableView *)[self fileListTable:NO nameTitle:LDLocalized(@"Name") autosaveName:@"LinDirStatLargestFiles" columnList:LDColumnListLargest];
  [_largestTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"physicalSize" ascending:NO]]];
  _searchTable = (LDTableView *)[self fileListTable:NO nameTitle:LDLocalized(@"Name") autosaveName:@"LinDirStatSearchResults" columnList:LDColumnListSearch];
  [_searchTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"logicalSize" ascending:NO]]];
  _duplicatesTable = (LDOutlineView *)[self fileListTable:YES nameTitle:LDLocalized(@"Hash Prefix / Name") autosaveName:@"LinDirStatDuplicates" columnList:LDColumnListDuplicates];
  [_duplicatesTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"physicalSize" ascending:NO]]];
  _largestFiles = @[];
  _duplicateGroups = @[];

  _fileTabs = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 700, 300)];
  [_fileTabs setDelegate:self];
  [_fileTabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _allFilesTab = [self tabItemWithIdentifier:LDTabAllFiles label:LDLocalized(@"All Files") view:[self scrollViewWithDocumentView:_directoryTable]];
  _largestTab = [self tabItemWithIdentifier:LDTabLargest label:LDLocalized(@"Largest Files") view:[self scrollViewWithDocumentView:_largestTable]];
  _duplicatesTab = [self tabItemWithIdentifier:LDTabDuplicates label:LDLocalized(@"Duplicate Files") view:[self scrollViewWithDocumentView:_duplicatesTable]];
  _searchTab = [self tabItemWithIdentifier:LDTabSearch label:LDLocalized(@"Search Results") view:[self scrollViewWithDocumentView:_searchTable]];
  _watcherTable = [self buildWatcherTable];
  _watcherEvents = [[NSMutableArray alloc] init];
  _watcherRows = @[];
  _watcherTab = [self tabItemWithIdentifier:LDTabWatcher label:LDLocalized(@"File Watcher") view:[self buildWatcherPane]];
  [_fileTabs addTabViewItem:_allFilesTab];
  [_fileTabs addTabViewItem:_largestTab];
  return _fileTabs;
}

// Hidden tabs are removed, not disabled (FileTabbedView.cpp).
- (void)setTab:(NSTabViewItem *)tab shown:(BOOL)shown
{
  BOOL present = [[_fileTabs tabViewItems] indexOfObjectIdenticalTo:tab] != NSNotFound;
  if (shown && !present) {
    [_fileTabs addTabViewItem:tab];
  } else if (!shown && present) {
    if ([_fileTabs selectedTabViewItem] == tab) {
      [_fileTabs selectTabViewItem:_allFilesTab];
    }
    [_fileTabs removeTabViewItem:tab];
  }
}

- (NSTableView *)activeFileList
{
  id identifier = [[_fileTabs selectedTabViewItem] identifier];
  if ([identifier isEqual:LDTabLargest]) {
    return _largestTable;
  }
  if ([identifier isEqual:LDTabDuplicates]) {
    return _duplicatesTable;
  }
  if ([identifier isEqual:LDTabSearch]) {
    return _searchTable;
  }
  if ([identifier isEqual:LDTabWatcher]) {
    return _watcherTable;
  }
  return _directoryTable;
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item
{
  (void)tabView;
  if (item == _largestTab) {
    [self updateLargestFiles];
  }
  // A list in a hidden tab has no width to fit into until it is shown.
  [self fitFlexibleColumns];
  [_window makeFirstResponder:[self activeFileList]];
  [self fileListSelectionDidChange:[self activeFileList]];
}

#pragma mark - Selection

// Nodes selected in a list other than the tree; group rows stand for their
// files.
- (NSArray *)selectedNodesInFileList:(NSTableView *)table
{
  NSMutableArray *nodes = [NSMutableArray array];
  NSIndexSet *rows = [table selectedRowIndexes];
  NSUInteger row = rows ? [rows firstIndex] : NSNotFound;
  while (row != NSNotFound) {
    id item = nil;
    if (table == _duplicatesTable) {
      item = [_duplicatesTable itemAtRow:(NSInteger)row];
    } else if (table == _largestTable) {
      item = row < [_largestFiles count] ? [_largestFiles objectAtIndex:row] : nil;
    } else if (table == _searchTable) {
      item = row < [_searchRows count] ? [_searchRows objectAtIndex:row] : nil;
    } else if (table == _watcherTable) {
      // A watcher row stands for the item still in the tree at its path.
      item = row < [_watcherRows count] ? [self nodeForPathData:[[_watcherRows objectAtIndex:row] pathData]] : nil;
    }
    if ([item isKindOfClass:[LDDuplicateGroup class]]) {
      for (LDFileNode *node in [(LDDuplicateGroup *)item nodes]) {
        if ([nodes indexOfObjectIdenticalTo:node] == NSNotFound) {
          [nodes addObject:node];
        }
      }
    } else if (item && [nodes indexOfObjectIdenticalTo:item] == NSNotFound) {
      [nodes addObject:item];
    }
    row = [rows indexGreaterThanIndex:row];
  }
  return nodes;
}

- (void)fileListSelectionDidChange:(NSTableView *)table
{
  if (table == _directoryTable) {
    return;
  }
  NSArray *nodes = [self selectedNodesInFileList:table];
  LDFileNode *node = [nodes lastObject];
  [_treemapView setHighlightedExtensionKey:nil];
  [_treemapView setSelectedNode:node];
  if (node) {
    [self showStatus:[self statusForSelection:nodes]];
  }
  [self updateSelectionField];
  [self refreshCommandState];
}

#pragma mark - Largest files

- (void)updateLargestFiles
{
  NSUInteger count = [[LDPreferences sharedPreferences] largeFileCount];
  [self showLargestFiles:_rootNode ? [LDLargestFiles largestFilesUnderNode:_rootNode count:count] : @[]];
}

- (void)showLargestFiles:(NSArray *)files
{
  NSArray *selected = [self selectedNodesInFileList:_largestTable];
  _largestFiles = [self sortedFileListRows:files forTable:_largestTable];
  [_largestTable reloadData];
  [self reselectNodes:selected inTable:_largestTable rows:_largestFiles];
}

- (void)reselectNodes:(NSArray *)nodes inTable:(NSTableView *)table rows:(NSArray *)rows
{
  NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
  for (LDFileNode *node in nodes) {
    NSUInteger index = [rows indexOfObjectIdenticalTo:node];
    if (index != NSNotFound) {
      [indexes addIndex:index];
    }
  }
  _syncingSelection = YES;
  [table selectRowIndexes:indexes byExtendingSelection:NO];
  _syncingSelection = NO;
}

- (NSComparisonResult)compareFileRow:(id)left with:(id)right key:(NSString *)key
{
  if ([key isEqualToString:@"path"]) {
    NSString *a = [left isKindOfClass:[LDDuplicateGroup class]] ? [left hashString] : [left path];
    NSString *b = [right isKindOfClass:[LDDuplicateGroup class]] ? [right hashString] : [right path];
    return [a compare:b];
  }
  unsigned long long a = 0;
  unsigned long long b = 0;
  if ([key isEqualToString:@"items"]) {
    a = [left isKindOfClass:[LDDuplicateGroup class]] ? [left count] : 1;
    b = [right isKindOfClass:[LDDuplicateGroup class]] ? [right count] : 1;
  } else if ([key isEqualToString:@"logicalSize"]) {
    a = [left isKindOfClass:[LDDuplicateGroup class]] ? [left totalLogicalSize] : [left aggregateSize];
    b = [right isKindOfClass:[LDDuplicateGroup class]] ? [right totalLogicalSize] : [right aggregateSize];
  } else if ([key isEqualToString:@"lastChange"]) {
    a = [left isKindOfClass:[LDFileNode class]] ? (unsigned long long)[left modificationTime] : 0;
    b = [right isKindOfClass:[LDFileNode class]] ? (unsigned long long)[right modificationTime] : 0;
  } else {
    a = [left isKindOfClass:[LDDuplicateGroup class]] ? [left totalPhysicalSize] : [left aggregateAllocatedSize];
    b = [right isKindOfClass:[LDDuplicateGroup class]] ? [right totalPhysicalSize] : [right aggregateAllocatedSize];
  }
  return a < b ? NSOrderedAscending : (a > b ? NSOrderedDescending : NSOrderedSame);
}

- (NSArray *)sortedFileListRows:(NSArray *)rows forTable:(NSTableView *)table
{
  NSSortDescriptor *descriptor = [[table sortDescriptors] firstObject];
  NSString *key = descriptor ? [descriptor key] : @"physicalSize";
  BOOL ascending = descriptor ? [descriptor ascending] : NO;
  return [rows sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
    NSComparisonResult result = [self compareFileRow:left with:right key:key];
    if (result == NSOrderedSame && ![key isEqualToString:@"path"]) {
      result = [self compareFileRow:left with:right key:@"path"];
      return result;
    }
    return ascending ? result : (NSComparisonResult)-result;
  }];
}

#pragma mark - Duplicates

- (void)setDuplicatesSearching:(BOOL)searching
{
  [_duplicatesTab setLabel:searching ? LDLocalized(@"Duplicate Files (searching…)") : LDLocalized(@"Duplicate Files")];
  [_fileTabs setNeedsDisplay:YES];
}

// WinDirStat hashes while it scans, so the Duplicates tab fills live. The
// scan's collector reports its groups a couple of times a second, and goes
// on hashing after the scan is complete.
- (void)fileListsDidStartScan
{
  LDDuplicateCollector *collector = [_scanSession duplicateCollector];
  [self setTab:_duplicatesTab shown:collector != nil];
  if (!collector) {
    return;
  }
  _duplicateFinder = collector;
  [self setDuplicatesSearching:YES];
  [collector setUpdateHandler:^(NSArray *groups, BOOL finished) {
    if (collector != _duplicateFinder) {
      return;
    }
    if (finished) {
      _duplicateFinder = nil;
      [self setDuplicatesSearching:NO];
    }
    [self showDuplicateGroupsKeepingSelection:groups];
  }];
}

// A scan with duplicate detection fills the tab as it goes. A tree that was
// not scanned that way (a loaded CSV) is hashed after the fact.
- (void)startDuplicateDetection
{
  LDDuplicateCollector *collector = [_scanSession duplicateCollector];
  if (collector) {
    if (_duplicateFinder != collector) {
      // The collector finished before the scan's completion arrived.
      [self showDuplicateGroupsKeepingSelection:[collector groups]];
    }
    return;
  }
  [_duplicateFinder cancel];
  _duplicateFinder = nil;
  _duplicateGroups = @[];
  [_duplicatesTable reloadData];
  BOOL enabled = [[LDPreferences sharedPreferences] scanForDuplicates] && _rootNode;
  [self setTab:_duplicatesTab shown:enabled];
  if (!enabled) {
    return;
  }
  LDDuplicateFinder *finder = [[LDDuplicateFinder alloc] initWithRootNode:_rootNode];
  _duplicateFinder = finder;
  [self setDuplicatesSearching:YES];
  [finder startWithProgress:^(NSUInteger hashedFiles, NSUInteger candidateFiles) {
    if (finder == _duplicateFinder) {
      [_duplicatesTab setLabel:[NSString stringWithFormat:LDLocalized(@"Duplicate Files (%lu%%)"),
                                candidateFiles ? (unsigned long)(hashedFiles * 100 / candidateFiles) : 0UL]];
      [_fileTabs setNeedsDisplay:YES];
    }
  } completion:^(NSArray *groups) {
    if (finder != _duplicateFinder) {
      return;
    }
    _duplicateFinder = nil;
    [self setDuplicatesSearching:NO];
    [self showDuplicateGroupsKeepingSelection:groups];
  }];
}

- (BOOL)isFindingDuplicates
{
  return _duplicateFinder != nil;
}

// A collector reports its groups so far once it has stopped; a finder run
// on a loaded tree reports nothing after it is cancelled.
- (void)stopDuplicateDetection
{
  if (!_duplicateFinder) {
    return;
  }
  [_duplicateFinder cancel];
  if ([_duplicateFinder isKindOfClass:[LDDuplicateFinder class]]) {
    _duplicateFinder = nil;
    [self setDuplicatesSearching:NO];
  }
  [self refreshCommandState];
}

// The tree may have changed while hashing; what left it is dropped.
- (void)showDuplicateGroupsKeepingSelection:(NSArray *)groups
{
  NSMutableArray *selected = [NSMutableArray array];
  NSIndexSet *rows = [_duplicatesTable selectedRowIndexes];
  for (NSUInteger row = [rows firstIndex]; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
    [selected addObject:[_duplicatesTable itemAtRow:(NSInteger)row]];
  }
  [self setDuplicateGroups:[self duplicateGroupsStillInTree:groups]];
  NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
  for (id item in selected) {
    NSInteger row = [_duplicatesTable rowForItem:item];
    if (row >= 0) {
      [indexes addIndex:(NSUInteger)row];
    }
  }
  _syncingSelection = YES;
  [_duplicatesTable selectRowIndexes:indexes byExtendingSelection:NO];
  _syncingSelection = NO;
}

- (void)setDuplicateGroups:(NSArray *)groups
{
  _duplicateGroups = [self sortedFileListRows:groups forTable:_duplicatesTable];
  [_duplicatesTable reloadData];
  [self refreshCommandState];
}

#pragma mark - Search

- (void)search:(id)sender
{
  (void)sender;
  if (!_rootNode || [self isBusy]) {
    return;
  }
  LDSearchOptions *options = [LDSearchPanel runSearchPanel];
  if (options) {
    [self showSearchResultsForOptions:options];
  }
}

// The selected extension list row's extension; nil for none or the grouped
// row, which has no single extension.
- (NSString *)selectedExtensionKey
{
  NSInteger row = [_extensionTable selectedRow];
  if (row < 0 || row >= (NSInteger)[_extensionRows count]) {
    return nil;
  }
  LDExtensionStats *stats = [_extensionRows objectAtIndex:(NSUInteger)row];
  return [stats isGroup] ? nil : [stats extensionKey];
}

// WinDirStat's "Extension - Search" (9ed686b1): the files with the selected
// extension, in Search Results.
- (void)searchExtension:(id)sender
{
  (void)sender;
  NSString *key = [self selectedExtensionKey];
  if (key) {
    [self showSearchResultsForOptions:[LDSearchOptions optionsForExtensionKey:key]];
  }
}

// A double-click on a row (not the header) searches (0cdff4c3).
- (void)extensionListDoubleClicked:(id)sender
{
  if ([_extensionTable clickedRow] >= 0 && [self validateAction:@selector(searchExtension:)]) {
    [self searchExtension:sender];
  }
}

- (void)showSearchResultsForOptions:(LDSearchOptions *)options
{
  if (!_rootNode || [self isBusy]) {
    return;
  }
  LDSearchResult *result = [LDSearch searchNode:_rootNode
                                        options:options
                                     maxResults:[[LDPreferences sharedPreferences] searchMaxResults]];
  _searchRows = [self sortedFileListRows:[result nodes] forTable:_searchTable];
  NSString *count = [NSString stringWithFormat:@"%lu%@", (unsigned long)[_searchRows count], [result isCapped] ? @"+" : @""];
  [_searchTab setLabel:[NSString stringWithFormat:LDLocalized(@"Search Results (%@)"), count]];
  [self setTab:_searchTab shown:YES];
  [_searchTable reloadData];
  [_fileTabs selectTabViewItem:_searchTab];
  // WinDirStat 2.7 shows the matches' totals (a match inside another once).
  unsigned long long total = _sizeMetric == LDSizeMetricLogical ? [result totalLogicalSize] : [result totalPhysicalSize];
  [self showStatus:[NSString stringWithFormat:LDLocalized(@"Found %@ items matching “%@”  ·  %@"),
                    count, [options term], [LDSizeFormatter stringForBytes:total]]];
}

#pragma mark - File watcher

- (LDTableView *)buildWatcherTable
{
  LDTableView *table = [[LDTableView alloc] initWithFrame:NSMakeRect(0, 0, 700, 300)];
  [table setCommandTarget:self];
  // FileTreeView.cpp: Name, Time, Operation, Logical Size, newest first.
  NSTableColumn *name = [self addColumn:@"path" title:LDLocalized(@"Name") width:420 right:NO toTable:table];
  [[name dataCell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [name setMinWidth:160.0];
  [self setSortPrototypeForColumn:name ascending:YES];
  [self setSortPrototypeForColumn:[self addColumn:@"time" title:LDLocalized(@"Time") width:150 right:NO toTable:table] ascending:NO];
  [self setSortPrototypeForColumn:[self addColumn:@"operation" title:LDLocalized(@"Operation") width:120 right:NO toTable:table] ascending:YES];
  [self setSortPrototypeForColumn:[self addColumn:@"logicalSize" title:LDLocalized(@"Logical Size") width:90 right:YES toTable:table] ascending:NO];
  [self addColumnChooserForTable:table list:LDColumnListWatcher required:nil changed:nil];
  [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  [table setAllowsMultipleSelection:YES];
  [table setAllowsColumnSelection:NO];
  [table setAutosaveName:@"LinDirStatFileWatcher"];
  [table setAutosaveTableColumns:YES];
  [table setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"time" ascending:NO]]];
  [table setDataSource:self];
  [table setDelegate:self];
  _watcherTimeFormatter = [[NSDateFormatter alloc] init];
  [_watcherTimeFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
  return table;
}

- (NSButton *)watcherButtonWithIcon:(NSString *)icon title:(NSString *)title action:(SEL)action
{
  NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 32, 28)];
  [button setTitle:@""];
  [button setImage:[LDPlatformUI toolbarImageNamed:icon label:title]];
  [button setImagePosition:NSImageOnly];
  [button setBezelStyle:NSRoundedBezelStyle];
  [button setToolTip:title];
  [button setTarget:self];
  [button setAction:action];
  return button;
}

// WinDirStat 2.7 (5dc5a134, 329f9c91) shows Start, Pause, Auto Scroll, Clear
// and a path filter in its toolbar while the File Watcher tab is active;
// here they head the tab itself.
- (NSView *)buildWatcherPane
{
  const CGFloat width = 700.0, height = 300.0, bar = 36.0, margin = 4.0;
  NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
  [pane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSScrollView *scroll = [self scrollViewWithDocumentView:_watcherTable];
  [scroll setFrame:NSMakeRect(0, 0, width, height - bar)];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [pane addSubview:scroll];

  _watcherStartButton = [self watcherButtonWithIcon:@"media-playback-start-symbolic" title:LDLocalized(@"Start")
                                             action:@selector(startWatching:)];
  _watcherPauseButton = [self watcherButtonWithIcon:@"media-playback-pause-symbolic" title:LDLocalized(@"Pause")
                                             action:@selector(pauseWatching:)];
  _watcherAutoScrollButton = [self watcherButtonWithIcon:@"go-bottom-symbolic" title:LDLocalized(@"Auto Scroll")
                                                  action:@selector(toggleWatcherAutoScroll:)];
  [_watcherAutoScrollButton setButtonType:NSPushOnPushOffButton];
  _watcherClearButton = [self watcherButtonWithIcon:@"edit-clear-all-symbolic" title:LDLocalized(@"Clear")
                                             action:@selector(clearWatcher:)];
  CGFloat x = margin;
  for (NSButton *button in @[_watcherStartButton, _watcherPauseButton, _watcherAutoScrollButton, _watcherClearButton]) {
    [button setFrameOrigin:NSMakePoint(x, height - bar + floor((bar - NSHeight([button frame])) / 2.0))];
    [button setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
    [pane addSubview:button];
    x += NSWidth([button frame]) + margin;
  }
  _watcherFilterField = [[NSSearchField alloc] initWithFrame:NSMakeRect(x + margin, height - bar + floor((bar - 24.0) / 2.0), 220, 24)];
  [[_watcherFilterField cell] setPlaceholderString:LDLocalized(@"Path Filter")];
  [_watcherFilterField setToolTip:LDLocalized(@"Path Filter")];
  [_watcherFilterField setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  [_watcherFilterField setDelegate:(id)self];
  [pane addSubview:_watcherFilterField];
  [self updateWatcherControls];
  return pane;
}

// OnUpdateWatcherStart/Pause/Clear: Start while not watching a scanned
// tree, Pause while watching, Clear while there are rows; Auto Scroll shows
// its setting.
- (void)updateWatcherControls
{
  [_watcherStartButton setEnabled:[self validateAction:@selector(startWatching:)]];
  [_watcherPauseButton setEnabled:[self validateAction:@selector(pauseWatching:)]];
  [_watcherClearButton setEnabled:[self validateAction:@selector(clearWatcher:)]];
  [_watcherAutoScrollButton setState:[[LDPreferences sharedPreferences] watcherAutoScroll] ? NSOnState : NSOffState];
}

- (void)startWatching:(id)sender
{
  (void)sender;
  if ([self validateAction:@selector(startWatching:)]) {
    [self startFileWatcher];
  }
  [self updateWatcherControls];
}

- (void)pauseWatching:(id)sender
{
  (void)sender;
  [_fileWatcher stop];
  _fileWatcher = nil;
  [self updateWatcherControls];
}

- (void)toggleWatcherAutoScroll:(id)sender
{
  (void)sender;
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  [preferences setWatcherAutoScroll:![preferences watcherAutoScroll]];
  [self updateWatcherControls];
  [self scrollWatcherToNewest];
}

// ClearResults: the rows, and those the filter hides, go; watching goes on.
- (void)clearWatcher:(id)sender
{
  (void)sender;
  [_watcherEvents removeAllObjects];
  [self reloadWatcherRows];
  [self updateWatcherControls];
}

// SetQuickFilter: the list shows the events whose path the expression
// matches; an invalid one leaves the list as it was and says so.
- (void)controlTextDidChange:(NSNotification *)notification
{
  if ([notification object] != _watcherFilterField) {
    return;
  }
  LDFileWatcherPathFilter *filter = [LDFileWatcherPathFilter filterWithPattern:[_watcherFilterField stringValue]];
  if (!filter) {
    [self showStatus:LDLocalized(@"The path filter is not a valid regular expression.")];
    return;
  }
  _watcherFilter = filter;
  [self showSummaryStatus];
  [self reloadWatcherRows];
  [self scrollWatcherToNewest];
}

// With Auto Scroll on, the latest change stays in view, wherever the sort
// puts it.
- (void)scrollWatcherToNewest
{
  if (![[LDPreferences sharedPreferences] watcherAutoScroll]) {
    return;
  }
  for (LDFileWatcherEvent *event in [_watcherEvents reverseObjectEnumerator]) {
    NSUInteger row = [_watcherRows indexOfObjectIdenticalTo:event];
    if (row != NSNotFound) {
      [_watcherTable scrollRowToVisible:(NSInteger)row];
      return;
    }
  }
}

- (BOOL)isFileWatcherOn
{
  return _watcherWanted;
}

// WinDirStat watches the root, or each drive under "This Computer".
- (NSArray *)watcherRootPaths
{
  NSArray *roots = [_rootNode isComputer] ? [_rootNode children] : (_rootNode ? @[_rootNode] : @[]);
  NSMutableArray *paths = [NSMutableArray array];
  for (LDFileNode *root in roots) {
    [paths addObject:[root pathData]];
  }
  return paths;
}

- (void)startFileWatcher
{
  [_fileWatcher stop];
  LDFileWatcher *watcher = [[LDFileWatcher alloc] initWithRootPaths:[self watcherRootPaths]];
  [watcher setEventHandler:^(NSArray *events) {
    [self addWatcherEvents:events];
  }];
  [watcher setMessageHandler:^(NSString *message) {
    [self showStatus:message];
  }];
  NSError *error = nil;
  if (![watcher startWithError:&error]) {
    _fileWatcher = nil;
    _watcherWanted = NO;
    [self setTab:_watcherTab shown:NO];
    [LDDialogs showFailures:@[[error localizedDescription] ?: LDLocalized(@"Unknown error")] title:LDLocalized(@"The file watcher could not start")];
    return;
  }
  _fileWatcher = watcher;
  [self updateWatcherControls];
}

// MainFrame.cpp OnToolsWatcher: the tab shows and watching starts, or the
// tab hides and watching stops. Rows are kept until the next scan.
- (void)toggleFileWatcher:(id)sender
{
  (void)sender;
  if (_watcherWanted) {
    _watcherWanted = NO;
    [_fileWatcher stop];
    _fileWatcher = nil;
    [self setTab:_watcherTab shown:NO];
    return;
  }
  if (!_rootNode || ![LDFileWatcher isSupported]) {
    return;
  }
  _watcherWanted = YES;
  [self setTab:_watcherTab shown:YES];
  [_fileTabs selectTabViewItem:_watcherTab];
  [self startFileWatcher];
}

- (void)addWatcherEvents:(NSArray *)events
{
  [_watcherEvents addObjectsFromArray:events];
  NSUInteger maximum = [LDFileWatcher maximumListedEvents];
  if ([_watcherEvents count] > maximum) {
    [_watcherEvents removeObjectsInRange:NSMakeRange(0, [_watcherEvents count] - maximum)];
  }
  [self reloadWatcherRows];
  [self scrollWatcherToNewest];
  [self updateWatcherControls];
}

- (NSComparisonResult)compareWatcherEvent:(LDFileWatcherEvent *)left with:(LDFileWatcherEvent *)right key:(NSString *)key
{
  if ([key isEqualToString:@"path"]) {
    return [[left path] compare:[right path]];
  }
  if ([key isEqualToString:@"operation"]) {
    return [[LDFileWatcherEvent titleForAction:[left action]] caseInsensitiveCompare:[LDFileWatcherEvent titleForAction:[right action]]];
  }
  if ([key isEqualToString:@"logicalSize"]) {
    return [left logicalSize] < [right logicalSize] ? NSOrderedAscending
      : ([left logicalSize] > [right logicalSize] ? NSOrderedDescending : NSOrderedSame);
  }
  return [left time] < [right time] ? NSOrderedAscending : ([left time] > [right time] ? NSOrderedDescending : NSOrderedSame);
}

// Rows in the list's order; ties keep the order the changes happened in
// (reversed when descending, so the newest change is on top).
- (void)reloadWatcherRows
{
  NSArray *selected = [_watcherRows objectsAtIndexes:[_watcherTable selectedRowIndexes]];
  NSSortDescriptor *descriptor = [[_watcherTable sortDescriptors] firstObject];
  NSString *key = descriptor ? [descriptor key] : @"time";
  BOOL ascending = descriptor ? [descriptor ascending] : NO;
  NSMutableArray *rows = [NSMutableArray arrayWithCapacity:[_watcherEvents count]];
  NSEnumerator *events = ascending ? [_watcherEvents objectEnumerator] : [_watcherEvents reverseObjectEnumerator];
  for (LDFileWatcherEvent *event in events) {
    if (!_watcherFilter || [(LDFileWatcherPathFilter *)_watcherFilter matchesEvent:event]) {
      [rows addObject:event];
    }
  }
  [rows sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id left, id right) {
    NSComparisonResult result = [self compareWatcherEvent:left with:right key:key];
    return ascending ? result : (NSComparisonResult)-result;
  }];
  _watcherRows = rows;
  [_watcherTable reloadData];
  NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
  for (LDFileWatcherEvent *event in selected) {
    NSUInteger index = [_watcherRows indexOfObjectIdenticalTo:event];
    if (index != NSNotFound) {
      [indexes addIndex:index];
    }
  }
  _syncingSelection = YES;
  [_watcherTable selectRowIndexes:indexes byExtendingSelection:NO];
  _syncingSelection = NO;
}

- (id)watcherValueForColumn:(NSString *)identifier event:(LDFileWatcherEvent *)event
{
  if ([identifier isEqualToString:@"path"]) {
    return [self displayPath:[event path]];
  }
  if ([identifier isEqualToString:@"time"]) {
    return [_watcherTimeFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[event time]]];
  }
  if ([identifier isEqualToString:@"operation"]) {
    return [LDFileWatcherEvent titleForAction:[event action]];
  }
  if ([identifier isEqualToString:@"logicalSize"]) {
    return [LDSizeFormatter stringForBytes:[event logicalSize]];
  }
  return @"";
}

#pragma mark - Keeping the lists in step with the tree

- (NSArray *)nodesStillInTree:(NSArray *)nodes
{
  NSMutableArray *kept = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    if ([_rootNode isAncestorOf:node]) {
      [kept addObject:node];
    }
  }
  return kept;
}

// After a refresh or deletion: drop rows for nodes that left the tree.
- (void)fileListsDidChangeTree
{
  [self updateLargestFiles];
  NSArray *selected = [self selectedNodesInFileList:_searchTable];
  NSUInteger searchCount = [_searchRows count];
  _searchRows = [self nodesStillInTree:_searchRows];
  if ([_searchRows count] != searchCount) {
    [_searchTab setLabel:[NSString stringWithFormat:LDLocalized(@"Search Results (%lu)"), (unsigned long)[_searchRows count]]];
    [_fileTabs setNeedsDisplay:YES];
  }
  [_searchTable reloadData];
  [self reselectNodes:selected inTable:_searchTable rows:_searchRows];
  [self setDuplicateGroups:[self duplicateGroupsStillInTree:_duplicateGroups]];
}

- (NSArray *)duplicateGroupsStillInTree:(NSArray *)duplicateGroups
{
  // Nothing has left the tree since the scan (every node that leaves it is,
  // or is below, a detached subtree): checking a million group members
  // would only stall the main thread.
  if ([_detachedSubtrees count] == 0) {
    return duplicateGroups;
  }
  NSMutableArray *groups = [NSMutableArray array];
  for (LDDuplicateGroup *group in duplicateGroups) {
    NSArray *kept = [self nodesStillInTree:[group nodes]];
    if ([kept count] == [[group nodes] count]) {
      [groups addObject:group];
    } else if ([kept count] >= 2) {
      unsigned long long physical = 0;
      for (LDFileNode *node in kept) {
        physical += [node allocatedSize];
      }
      [groups addObject:[[LDDuplicateGroup alloc] initWithHashString:[group hashString]
                                                         logicalSize:[group logicalSize]
                                                               nodes:kept
                                                   totalPhysicalSize:physical]];
    }
  }
  return groups;
}

// A new scan starts with All Files and no search results. The File Watcher
// tab stays while it is on and empties; it watches the new tree once the
// scan is done (WinDirStat just stops it, DirStatDoc.cpp DeleteContents).
- (void)resetFileListsForScan
{
  [_fileWatcher stop];
  _fileWatcher = nil;
  [_watcherEvents removeAllObjects];
  _watcherRows = @[];
  [_watcherTable reloadData];
  [_duplicateFinder cancel];
  _duplicateFinder = nil;
  _largestFiles = @[];
  _duplicateGroups = @[];
  _searchRows = @[];
  [self setTab:_searchTab shown:NO];
  [self setTab:_duplicatesTab shown:NO];
  [_fileTabs selectTabViewItem:_allFilesTab];
  [_largestTable reloadData];
  [_duplicatesTable reloadData];
  [_searchTable reloadData];
}

- (void)fileListsDidFinishScanWithLargestFiles:(NSArray *)largestFiles
{
  if (largestFiles) {
    [self showLargestFiles:largestFiles];
  } else {
    [self updateLargestFiles];
  }
  [self startDuplicateDetection];
  if (_watcherWanted) {
    [self startFileWatcher];
  }
}

#pragma mark - Data

- (BOOL)isFileList:(NSTableView *)table
{
  return table == _largestTable || table == _searchTable || table == _duplicatesTable || table == _watcherTable;
}

- (NSArray *)rowsOfFileList:(NSTableView *)table
{
  if (table == _watcherTable) {
    return _watcherRows;
  }
  return table == _largestTable ? _largestFiles : (table == _searchTable ? _searchRows : _duplicateGroups);
}

- (id)fileListValueForColumn:(NSString *)identifier item:(id)item
{
  if ([item isKindOfClass:[LDFileWatcherEvent class]]) {
    return [self watcherValueForColumn:identifier event:item];
  }
  if ([item isKindOfClass:[LDDuplicateGroup class]]) {
    LDDuplicateGroup *group = item;
    if ([identifier isEqualToString:@"path"]) {
      return [NSString stringWithFormat:@"%@ %@", [group hashString], [group extensionsLabel]];
    }
    if ([identifier isEqualToString:@"items"]) {
      return [NSString stringWithFormat:@"%lu", (unsigned long)[group count]];
    }
    if ([identifier isEqualToString:@"physicalSize"]) {
      return [LDSizeFormatter stringForBytes:[group totalPhysicalSize]];
    }
    if ([identifier isEqualToString:@"logicalSize"]) {
      return [LDSizeFormatter stringForBytes:[group totalLogicalSize]];
    }
    return @"";
  }
  LDFileNode *node = item;
  if ([identifier isEqualToString:@"path"]) {
    return [self displayPath:[node path]];
  }
  if ([identifier isEqualToString:@"physicalSize"]) {
    return [LDSizeFormatter stringForBytes:[node aggregateAllocatedSize]];
  }
  if ([identifier isEqualToString:@"logicalSize"]) {
    return [LDSizeFormatter stringForBytes:[node aggregateSize]];
  }
  if ([identifier isEqualToString:@"lastChange"]) {
    NSTimeInterval time = [node modificationTime];
    return time > 0 ? [_dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]] : @"";
  }
  return @"";
}

- (void)fileListSortDescriptorsDidChange:(NSTableView *)table
{
  NSArray *selected = [self selectedNodesInFileList:table];
  if (table == _largestTable) {
    _largestFiles = [self sortedFileListRows:_largestFiles forTable:table];
    [table reloadData];
    [self reselectNodes:selected inTable:table rows:_largestFiles];
  } else if (table == _searchTable) {
    _searchRows = [self sortedFileListRows:_searchRows forTable:table];
    [table reloadData];
    [self reselectNodes:selected inTable:table rows:_searchRows];
  } else if (table == _watcherTable) {
    [self reloadWatcherRows];
  } else {
    [self setDuplicateGroups:_duplicateGroups];
  }
}

#pragma mark - CSV and hashes

- (NSString *)runSavePanelWithTitle:(NSString *)title name:(NSString *)name
{
  NSSavePanel *panel = [NSSavePanel savePanel];
  [panel setTitle:title];
  [panel setRequiredFileType:@"csv"];
  NSInteger result = [panel runModalForDirectory:nil file:name];
  if (result != NSFileHandlingPanelOKButton && result != NSOKButton) {
    return nil;
  }
  return [panel filename];
}

- (void)saveResultsToCSV:(id)sender
{
  (void)sender;
  if (!_rootNode || [self isBusy]) {
    return;
  }
  NSString *path = [self runSavePanelWithTitle:LDLocalized(@"Save Results To CSV") name:LDLocalized(@"LinDirStat.csv")];
  if (!path) {
    return;
  }
  NSError *error = nil;
  BOOL includeOwner = [[LDPreferences sharedPreferences] isColumnShown:LDColumnOwner];
  if (![LDCSV writeTree:_rootNode toPath:path includeOwner:includeOwner error:&error]) {
    [LDDialogs showFailures:@[[error localizedDescription] ?: LDLocalized(@"Unknown error")] title:LDLocalized(@"Saving the results failed")];
    return;
  }
  [self showStatus:[NSString stringWithFormat:LDLocalized(@"Saved %@"), [self displayPath:path]]];
}

- (void)saveDuplicatesToCSV:(id)sender
{
  (void)sender;
  if ([_duplicateGroups count] == 0) {
    return;
  }
  NSString *path = [self runSavePanelWithTitle:LDLocalized(@"Save Duplicates To CSV") name:LDLocalized(@"LinDirStat Duplicates.csv")];
  if (!path) {
    return;
  }
  NSError *error = nil;
  if (![LDCSV writeDuplicateGroups:_duplicateGroups toPath:path error:&error]) {
    [LDDialogs showFailures:@[[error localizedDescription] ?: LDLocalized(@"Unknown error")] title:LDLocalized(@"Saving the duplicates failed")];
    return;
  }
  [self showStatus:[NSString stringWithFormat:LDLocalized(@"Saved %@"), [self displayPath:path]]];
}

- (void)loadResultsFromCSV:(id)sender
{
  (void)sender;
  if ([self isBusy]) {
    return;
  }
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setTitle:LDLocalized(@"Load Results From CSV")];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowsMultipleSelection:NO];
  NSInteger result = [panel runModalForDirectory:nil file:nil types:@[@"csv"]];
  if (result != NSFileHandlingPanelOKButton && result != NSOKButton) {
    return;
  }
  [self loadResultsFromCSVFile:[[panel filenames] firstObject] ?: [panel filename]];
}

- (void)loadResultsFromCSVFile:(NSString *)path
{
  NSError *error = nil;
  LDFileNode *root = [LDCSV readTreeFromPath:path
                            processHardLinks:[[LDPreferences sharedPreferences] processHardLinks]
                                       error:&error];
  if (!root) {
    [LDDialogs showFailures:@[[error localizedDescription] ?: LDLocalized(@"Unknown error")] title:LDLocalized(@"Loading the results failed")];
    return;
  }
  [self showLoadedTree:root fromFile:path];
}

- (void)computeHash:(id)sender
{
  (void)sender;
  NSArray *nodes = [self selectedNodes];
  if ([nodes count] != 1) {
    return;
  }
  LDFileNode *node = [nodes objectAtIndex:0];
  NSData *path = [node pathData];
  NSString *displayPath = [node path];
  [self showStatus:[NSString stringWithFormat:LDLocalized(@"Computing hashes of %@…"), [self displayPath:displayPath]]];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *error = nil;
    NSDictionary *hashes = [LDHasher hashesForFileAtPath:path error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self showSummaryStatus];
      if (!hashes) {
        [LDDialogs showFailures:@[[NSString stringWithFormat:@"%@: %@", displayPath, [error localizedDescription]]]
                          title:LDLocalized(@"Computing hashes failed")];
        return;
      }
      NSMutableArray *lines = [NSMutableArray arrayWithObject:displayPath];
      for (NSString *name in [LDHasher hashAlgorithmNames]) {
        [lines addObject:[NSString stringWithFormat:@"%-7@ %@", name, [hashes objectForKey:name]]];
      }
      [LDDialogs showText:[lines componentsJoinedByString:@"\n"] title:LDLocalized(@"Hashes")];
    });
  });
}

@end

// WinDirStat's Search dialog (SearchDlg.cpp): a term and three options,
// remembered between searches; OK is disabled while the term is empty or
// the regular expression is invalid.
@implementation LDSearchPanel

- (NSButton *)checkbox:(NSString *)title frame:(NSRect)frame state:(BOOL)state in:(NSView *)content
{
  NSButton *box = [[NSButton alloc] initWithFrame:frame];
  [box setButtonType:NSSwitchButton];
  [box setTitle:title];
  [box setState:state ? NSOnState : NSOffState];
  [box setTarget:self];
  [box setAction:@selector(optionsChanged:)];
  [content addSubview:box];
  return box;
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame tag:(NSInteger)tag in:(NSView *)content
{
  NSButton *button = [[NSButton alloc] initWithFrame:frame];
  [button setTitle:title];
  [button setBezelStyle:NSRoundedBezelStyle];
  [button setTag:tag];
  [button setTarget:self];
  [button setAction:@selector(finish:)];
  [content addSubview:button];
  return button;
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame in:(NSView *)content
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  [label setStringValue:text];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:NO];
  [content addSubview:label];
  return label;
}

- (NSTextField *)field:(NSString *)value frame:(NSRect)frame in:(NSView *)content
{
  NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
  [field setStringValue:value ?: @""];
  [field setDelegate:(id)self];
  [content addSubview:field];
  return field;
}

- (NSPopUpButton *)unitsPopUp:(NSInteger)selected frame:(NSRect)frame in:(NSView *)content
{
  NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
  [popUp addItemsWithTitles:@[@"bytes", @"KiB", @"MiB", @"GiB", @"TiB"]];
  [popUp selectItemAtIndex:selected];
  [popUp setTarget:self];
  [popUp setAction:@selector(optionsChanged:)];
  [content addSubview:popUp];
  return popUp;
}

+ (LDSearchOptions *)runSearchPanel
{
  return [[[LDSearchPanel alloc] init] run];
}

// Each size bound, or nil; NO when a field is not a whole number.
- (BOOL)readBound:(NSTextField *)field unit:(NSPopUpButton *)unit into:(NSNumber **)bound
{
  id bytes = [LDSearch bytesForSizeField:[field stringValue] unit:[unit indexOfSelectedItem]];
  if (bytes == [NSNull null]) {
    return NO;
  }
  *bound = bytes;
  return YES;
}

- (LDSearchOptions *)currentOptions
{
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:[_termField stringValue]];
  [options setUsesRegex:[_regexBox state] == NSOnState];
  [options setCaseSensitive:[_caseBox state] == NSOnState];
  [options setWholePhrase:[_wholeBox state] == NSOnState];
  [options setIncludesFiles:[_filesBox state] == NSOnState];
  [options setIncludesFolders:[_foldersBox state] == NSOnState];
  [options setOwner:[[_ownerField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
  NSNumber *bound = nil;
  if (![self readBound:_logicalMinimum unit:_logicalUnit into:&bound]) return nil;
  [options setLogicalMinimum:bound];
  bound = nil;
  if (![self readBound:_logicalMaximum unit:_logicalUnit into:&bound]) return nil;
  [options setLogicalMaximum:bound];
  bound = nil;
  if (![self readBound:_physicalMinimum unit:_physicalUnit into:&bound]) return nil;
  [options setPhysicalMinimum:bound];
  bound = nil;
  if (![self readBound:_physicalMaximum unit:_physicalUnit into:&bound]) return nil;
  [options setPhysicalMaximum:bound];
  return options;
}

- (void)validate
{
  LDSearchOptions *options = [self currentOptions];
  NSError *error = nil;
  BOOL valid = options && [LDSearch validateOptions:options error:&error];
  [_okButton setEnabled:valid];
  NSString *message = options ? [error localizedDescription] : LDLocalized(@"Sizes are whole numbers.");
  [_errorLabel setStringValue:valid ? @"" : (message ?: @"")];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
  // Typing '*' as a glob implies matching the whole name.
  if ([notification object] == _termField && [_regexBox state] != NSOnState
      && [LDSearch termImpliesWholePhrase:[_termField stringValue]]) {
    [_wholeBox setState:NSOnState];
  }
  [self validate];
}

// A term from the history brings back the switches it was searched with.
- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
  NSInteger index = [_termField indexOfSelectedItem];
  if (index < 0 || index >= (NSInteger)[_history count]) {
    return;
  }
  NSDictionary *entry = [_history objectAtIndex:(NSUInteger)index];
  [_regexBox setState:[[entry objectForKey:@"Regex"] boolValue] ? NSOnState : NSOffState];
  [_wholeBox setState:[[entry objectForKey:@"WholePhrase"] boolValue] ? NSOnState : NSOffState];
  [_caseBox setState:[[entry objectForKey:@"Case"] boolValue] ? NSOnState : NSOffState];
  (void)notification;
  [self validate];
}

- (void)optionsChanged:(id)sender
{
  (void)sender;
  [self validate];
}

- (void)finish:(id)sender
{
  [NSApp stopModalWithCode:[sender tag]];
}

// WinDirStat 2.7's Search dialog: the term with its history, the name
// switches beside the item types, then owner and the two size ranges.
- (LDSearchOptions *)run
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 500, 360)
                                              styleMask:NSTitledWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
  [panel setTitle:LDLocalized(@"Search")];
  [panel setReleasedWhenClosed:NO];
  NSView *content = [panel contentView];
  const CGFloat left = 18, labelWidth = 120, fieldLeft = left + labelWidth + 8, right = 482;

  [self label:LDLocalized(@"Search Term:") frame:NSMakeRect(left, 312, labelWidth, 22) in:content];
  _termField = [[NSComboBox alloc] initWithFrame:NSMakeRect(fieldLeft, 308, right - fieldLeft, 30)];
  _history = [preferences searchHistory];
  for (NSDictionary *entry in _history) {
    NSString *term = [entry isKindOfClass:[NSDictionary class]] ? [entry objectForKey:@"Term"] : nil;
    if ([term isKindOfClass:[NSString class]]) {
      [_termField addItemWithObjectValue:term];
    }
  }
  [_termField setNumberOfVisibleItems:10];
  [_termField setCompletes:NO];
  [_termField setStringValue:[preferences lastSearchTerm]];
  [_termField setDelegate:(id)self];
  [content addSubview:_termField];

  CGFloat column = fieldLeft + 220;
  _regexBox = [self checkbox:LDLocalized(@"Use Regular Expressions") frame:NSMakeRect(fieldLeft, 274, 216, 22)
                       state:[preferences searchUsesRegex] in:content];
  _wholeBox = [self checkbox:LDLocalized(@"Search Whole Phrase") frame:NSMakeRect(fieldLeft, 250, 216, 22)
                       state:[preferences searchWholePhrase] in:content];
  _caseBox = [self checkbox:LDLocalized(@"Case Sensitive Search") frame:NSMakeRect(fieldLeft, 226, 216, 22)
                      state:[preferences searchCaseSensitive] in:content];
  _filesBox = [self checkbox:LDLocalized(@"Files") frame:NSMakeRect(column, 274, right - column, 22)
                       state:[preferences searchIncludesFiles] in:content];
  _foldersBox = [self checkbox:LDLocalized(@"Folders") frame:NSMakeRect(column, 250, right - column, 22)
                         state:[preferences searchIncludesFolders] in:content];

  [self label:LDLocalized(@"Owner:") frame:NSMakeRect(left, 186, labelWidth, 22) in:content];
  _ownerField = [self field:[preferences searchOwner] frame:NSMakeRect(fieldLeft, 182, right - fieldLeft, 30) in:content];

  CGFloat fieldWidth = 90, dashWidth = 16;
  NSArray *rows = @[@[LDLocalized(@"Logical Size:"), @142, @"SearchSizeMinimum", @"SearchSizeMaximum"],
                    @[LDLocalized(@"Physical Size:"), @102, @"SearchPhysicalMinimum", @"SearchPhysicalMaximum"]];
  for (NSArray *row in rows) {
    CGFloat y = [[row objectAtIndex:1] doubleValue];
    [self label:[row objectAtIndex:0] frame:NSMakeRect(left, y + 4, labelWidth, 22) in:content];
    NSTextField *minimum = [self field:[preferences searchSizeField:[row objectAtIndex:2]]
                                 frame:NSMakeRect(fieldLeft, y, fieldWidth, 30) in:content];
    [minimum setPlaceholderString:@"0"];
    NSTextField *dash = [self label:@"–" frame:NSMakeRect(fieldLeft + fieldWidth, y + 4, dashWidth, 22) in:content];
    [dash setAlignment:NSCenterTextAlignment];
    NSTextField *maximum = [self field:[preferences searchSizeField:[row objectAtIndex:3]]
                                 frame:NSMakeRect(fieldLeft + fieldWidth + dashWidth, y, fieldWidth, 30) in:content];
    [maximum setPlaceholderString:@"∞"];
    CGFloat unitLeft = fieldLeft + 2 * fieldWidth + dashWidth + 8;
    BOOL logical = (row == [rows objectAtIndex:0]);
    NSPopUpButton *unit = [self unitsPopUp:logical ? [preferences searchSizeUnits] : [preferences searchPhysicalUnits]
                                     frame:NSMakeRect(unitLeft, y, right - unitLeft, 30) in:content];
    if (logical) {
      _logicalMinimum = minimum;
      _logicalMaximum = maximum;
      _logicalUnit = unit;
    } else {
      _physicalMinimum = minimum;
      _physicalMaximum = maximum;
      _physicalUnit = unit;
    }
  }

  _errorLabel = [self label:@"" frame:NSMakeRect(left, 60, right - left, 20) in:content];
  [_errorLabel setTextColor:[NSColor disabledControlTextColor]];
  [_errorLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  NSButton *cancel = [self button:LDLocalized(@"Cancel") frame:NSMakeRect(right - 210, 14, 100, 34) tag:0 in:content];
  [cancel setKeyEquivalent:@"\e"];
  _okButton = [self button:LDLocalized(@"Search") frame:NSMakeRect(right - 100, 14, 100, 34) tag:1 in:content];
  [_okButton setKeyEquivalent:@"\r"];
  [self validate];

  [panel center];
  [panel setInitialFirstResponder:_termField];
  [panel makeFirstResponder:_termField];
  NSInteger result = [NSApp runModalForWindow:panel];
  [panel orderOut:nil];
  LDSearchOptions *options = result == 1 ? [self currentOptions] : nil;
  if (!options) {
    return nil;
  }
  [preferences setLastSearchTerm:[options term]];
  [preferences setSearchUsesRegex:[options usesRegex]];
  [preferences setSearchCaseSensitive:[options caseSensitive]];
  [preferences setSearchWholePhrase:[options wholePhrase]];
  [preferences setSearchIncludesFiles:[options includesFiles]];
  [preferences setSearchIncludesFolders:[options includesFolders]];
  [preferences setSearchOwner:[options owner]];
  [preferences setSearchSizeField:[_logicalMinimum stringValue] forKey:@"SearchSizeMinimum"];
  [preferences setSearchSizeField:[_logicalMaximum stringValue] forKey:@"SearchSizeMaximum"];
  [preferences setSearchSizeField:[_physicalMinimum stringValue] forKey:@"SearchPhysicalMinimum"];
  [preferences setSearchSizeField:[_physicalMaximum stringValue] forKey:@"SearchPhysicalMaximum"];
  [preferences setSearchSizeUnits:[_logicalUnit indexOfSelectedItem]];
  [preferences setSearchPhysicalUnits:[_physicalUnit indexOfSelectedItem]];
  [preferences setSearchHistory:[LDSearch history:_history byAdding:options limit:[preferences searchHistoryCount]]];
  return options;
}

@end
