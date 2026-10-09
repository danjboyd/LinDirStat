#import "AppController.h"
#import "AppController+Private.h"
#import "LDCSV.h"
#import "LDDialogs.h"
#import "LDDuplicateFinder.h"
#import "LDHasher.h"
#import "LDLargestFiles.h"
#import "LDPreferences.h"
#import "LDScanSession.h"
#import "LDSearch.h"
#import "LDSizeFormatter.h"
#import "LDTreemapView.h"
#import "GSOpenSave.h"

static NSString *const LDTabAllFiles = @"all";
static NSString *const LDTabLargest = @"largest";
static NSString *const LDTabDuplicates = @"duplicates";
static NSString *const LDTabSearch = @"search";

// WinDirStat's tabbed file view (FileTabbedView.cpp): All Files, Largest
// Files, Duplicate Files (when duplicate detection is on) and Search Results
// (after a search). Each list's selection drives the treemap and commands.
@implementation AppController (FileLists)

#pragma mark - Building

- (NSTableView *)fileListTable:(BOOL)outline nameTitle:(NSString *)nameTitle autosaveName:(NSString *)autosaveName
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
    NSTableColumn *items = [self addColumn:@"items" title:@"Items" width:60 right:YES toTable:table];
    [self setSortPrototypeForColumn:items ascending:NO];
  }
  NSArray *columns = @[@[@"physicalSize", @"Physical Size"], @[@"logicalSize", @"Logical Size"]];
  for (NSArray *spec in columns) {
    NSTableColumn *column = [self addColumn:[spec objectAtIndex:0] title:[spec objectAtIndex:1] width:90 right:YES toTable:table];
    [self setSortPrototypeForColumn:column ascending:NO];
  }
  NSTableColumn *lastChange = [self addColumn:@"lastChange" title:@"Last Change" width:140 right:NO toTable:table];
  [self setSortPrototypeForColumn:lastChange ascending:YES];
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
  _largestTable = (LDTableView *)[self fileListTable:NO nameTitle:@"Name" autosaveName:@"LinDirStatLargestFiles"];
  [_largestTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"physicalSize" ascending:NO]]];
  _searchTable = (LDTableView *)[self fileListTable:NO nameTitle:@"Name" autosaveName:@"LinDirStatSearchResults"];
  [_searchTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"logicalSize" ascending:NO]]];
  _duplicatesTable = (LDOutlineView *)[self fileListTable:YES nameTitle:@"Hash Prefix / Name" autosaveName:@"LinDirStatDuplicates"];
  [_duplicatesTable setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"physicalSize" ascending:NO]]];
  _largestFiles = @[];
  _duplicateGroups = @[];

  _fileTabs = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 700, 300)];
  [_fileTabs setDelegate:self];
  [_fileTabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _allFilesTab = [self tabItemWithIdentifier:LDTabAllFiles label:@"All Files" view:[self scrollViewWithDocumentView:_directoryTable]];
  _largestTab = [self tabItemWithIdentifier:LDTabLargest label:@"Largest Files" view:[self scrollViewWithDocumentView:_largestTable]];
  _duplicatesTab = [self tabItemWithIdentifier:LDTabDuplicates label:@"Duplicate Files" view:[self scrollViewWithDocumentView:_duplicatesTable]];
  _searchTab = [self tabItemWithIdentifier:LDTabSearch label:@"Search Results" view:[self scrollViewWithDocumentView:_searchTable]];
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
  NSUInteger row = [rows firstIndex];
  while (row != NSNotFound) {
    id item = nil;
    if (table == _duplicatesTable) {
      item = [_duplicatesTable itemAtRow:(NSInteger)row];
    } else if (table == _largestTable) {
      item = row < [_largestFiles count] ? [_largestFiles objectAtIndex:row] : nil;
    } else if (table == _searchTable) {
      item = row < [_searchRows count] ? [_searchRows objectAtIndex:row] : nil;
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
    [self showStatus:[self describeNode:node]];
  }
  [self updateSelectionField];
  [self refreshCommandState];
}

#pragma mark - Largest files

- (void)updateLargestFiles
{
  NSUInteger count = [[LDPreferences sharedPreferences] largeFileCount];
  NSArray *files = _rootNode ? [LDLargestFiles largestFilesUnderNode:_rootNode count:count] : @[];
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

- (void)startDuplicateDetection
{
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
  [_duplicatesTab setLabel:@"Duplicate Files (searching…)"];
  [finder startWithProgress:^(NSUInteger hashedFiles, NSUInteger candidateFiles) {
    if (finder == _duplicateFinder) {
      [_duplicatesTab setLabel:[NSString stringWithFormat:@"Duplicate Files (%lu%%)",
                                candidateFiles ? (unsigned long)(hashedFiles * 100 / candidateFiles) : 0UL]];
      [_fileTabs setNeedsDisplay:YES];
    }
  } completion:^(NSArray *groups) {
    if (finder != _duplicateFinder) {
      return;
    }
    _duplicateFinder = nil;
    [_duplicatesTab setLabel:@"Duplicate Files"];
    [_fileTabs setNeedsDisplay:YES];
    [self setDuplicateGroups:groups];
  }];
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
  if (!options) {
    return;
  }
  LDSearchResult *result = [LDSearch searchNode:_rootNode
                                        options:options
                                     maxResults:[[LDPreferences sharedPreferences] searchMaxResults]];
  _searchRows = [self sortedFileListRows:[result nodes] forTable:_searchTable];
  NSString *count = [NSString stringWithFormat:@"%lu%@", (unsigned long)[_searchRows count], [result isCapped] ? @"+" : @""];
  [_searchTab setLabel:[NSString stringWithFormat:@"Search Results (%@)", count]];
  [self setTab:_searchTab shown:YES];
  [_searchTable reloadData];
  [_fileTabs selectTabViewItem:_searchTab];
  [self showStatus:[NSString stringWithFormat:@"Found %@ files matching “%@”", count, [options term]]];
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
  _searchRows = [self nodesStillInTree:_searchRows];
  [_searchTable reloadData];
  [self reselectNodes:selected inTable:_searchTable rows:_searchRows];
  NSMutableArray *groups = [NSMutableArray array];
  for (LDDuplicateGroup *group in _duplicateGroups) {
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
  [self setDuplicateGroups:groups];
}

// A new scan starts with All Files and no search results.
- (void)resetFileListsForScan
{
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

- (void)fileListsDidFinishScan
{
  [self updateLargestFiles];
  [self startDuplicateDetection];
}

#pragma mark - Data

- (BOOL)isFileList:(NSTableView *)table
{
  return table == _largestTable || table == _searchTable || table == _duplicatesTable;
}

- (NSArray *)rowsOfFileList:(NSTableView *)table
{
  return table == _largestTable ? _largestFiles : (table == _searchTable ? _searchRows : _duplicateGroups);
}

- (id)fileListValueForColumn:(NSString *)identifier item:(id)item
{
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
  NSString *path = [self runSavePanelWithTitle:@"Save Results To CSV" name:@"LinDirStat.csv"];
  if (!path) {
    return;
  }
  NSError *error = nil;
  BOOL includeOwner = [[LDPreferences sharedPreferences] isColumnShown:LDColumnOwner];
  if (![LDCSV writeTree:_rootNode toPath:path includeOwner:includeOwner error:&error]) {
    [LDDialogs showFailures:@[[error localizedDescription] ?: @"Unknown error"] title:@"Saving the results failed"];
    return;
  }
  [self showStatus:[NSString stringWithFormat:@"Saved %@", [self displayPath:path]]];
}

- (void)saveDuplicatesToCSV:(id)sender
{
  (void)sender;
  if ([_duplicateGroups count] == 0) {
    return;
  }
  NSString *path = [self runSavePanelWithTitle:@"Save Duplicates To CSV" name:@"LinDirStat Duplicates.csv"];
  if (!path) {
    return;
  }
  NSError *error = nil;
  if (![LDCSV writeDuplicateGroups:_duplicateGroups toPath:path error:&error]) {
    [LDDialogs showFailures:@[[error localizedDescription] ?: @"Unknown error"] title:@"Saving the duplicates failed"];
    return;
  }
  [self showStatus:[NSString stringWithFormat:@"Saved %@", [self displayPath:path]]];
}

- (void)loadResultsFromCSV:(id)sender
{
  (void)sender;
  if ([self isBusy]) {
    return;
  }
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setTitle:@"Load Results From CSV"];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowsMultipleSelection:NO];
  NSInteger result = [panel runModalForDirectory:nil file:nil types:@[@"csv"]];
  if (result != NSFileHandlingPanelOKButton && result != NSOKButton) {
    return;
  }
  NSString *path = [[panel filenames] firstObject] ?: [panel filename];
  NSError *error = nil;
  LDFileNode *root = [LDCSV readTreeFromPath:path error:&error];
  if (!root) {
    [LDDialogs showFailures:@[[error localizedDescription] ?: @"Unknown error"] title:@"Loading the results failed"];
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
  [self showStatus:[NSString stringWithFormat:@"Computing hashes of %@…", [self displayPath:displayPath]]];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *error = nil;
    NSDictionary *hashes = [LDHasher hashesForFileAtPath:path error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self showSummaryStatus];
      if (!hashes) {
        [LDDialogs showFailures:@[[NSString stringWithFormat:@"%@: %@", displayPath, [error localizedDescription]]]
                          title:@"Computing hashes failed"];
        return;
      }
      NSMutableArray *lines = [NSMutableArray arrayWithObject:displayPath];
      for (NSString *name in [LDHasher hashAlgorithmNames]) {
        [lines addObject:[NSString stringWithFormat:@"%-7@ %@", name, [hashes objectForKey:name]]];
      }
      [LDDialogs showText:[lines componentsJoinedByString:@"\n"] title:@"Hashes"];
    });
  });
}

@end

// WinDirStat's Search dialog (SearchDlg.cpp): a term and three options,
// remembered between searches; OK is disabled while the term is empty or
// the regular expression is invalid.
@implementation LDSearchPanel

- (NSButton *)checkbox:(NSString *)title y:(CGFloat)y state:(BOOL)state in:(NSView *)content
{
  NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(18, y, 400, 22)];
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

+ (LDSearchOptions *)runSearchPanel
{
  return [[[LDSearchPanel alloc] init] run];
}

- (LDSearchOptions *)currentOptions
{
  LDSearchOptions *options = [LDSearchOptions optionsWithTerm:[_termField stringValue]];
  [options setUsesRegex:[_regexBox state] == NSOnState];
  [options setCaseSensitive:[_caseBox state] == NSOnState];
  [options setWholePhrase:[_wholeBox state] == NSOnState];
  return options;
}

- (void)validate
{
  NSError *error = nil;
  BOOL valid = [LDSearch validateOptions:[self currentOptions] error:&error];
  [_okButton setEnabled:valid];
  [_errorLabel setStringValue:(valid || [[_termField stringValue] length] == 0) ? @"" : ([error localizedDescription] ?: @"")];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
  (void)notification;
  // Typing '*' as a glob implies matching the whole name.
  if ([_regexBox state] != NSOnState && [LDSearch termImpliesWholePhrase:[_termField stringValue]]) {
    [_wholeBox setState:NSOnState];
  }
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

- (LDSearchOptions *)run
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 236)
                                              styleMask:NSTitledWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
  [panel setTitle:@"Search"];
  [panel setReleasedWhenClosed:NO];
  NSView *content = [panel contentView];

  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 194, 424, 20)];
  [label setStringValue:@"Find files whose name contains:"];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [content addSubview:label];
  _termField = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 160, 424, 28)];
  [_termField setStringValue:[preferences lastSearchTerm]];
  [_termField setDelegate:(id)self];
  [content addSubview:_termField];
  _regexBox = [self checkbox:@"Use regular expressions (POSIX extended)" y:128 state:[preferences searchUsesRegex] in:content];
  _caseBox = [self checkbox:@"Case sensitive" y:104 state:[preferences searchCaseSensitive] in:content];
  _wholeBox = [self checkbox:@"Match the whole name" y:80 state:[preferences searchWholePhrase] in:content];
  _errorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 56, 424, 20)];
  [_errorLabel setBezeled:NO];
  [_errorLabel setDrawsBackground:NO];
  [_errorLabel setEditable:NO];
  [_errorLabel setTextColor:[NSColor disabledControlTextColor]];
  [_errorLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  [content addSubview:_errorLabel];
  NSButton *cancel = [self button:@"Cancel" frame:NSMakeRect(232, 14, 100, 34) tag:0 in:content];
  [cancel setKeyEquivalent:@"\e"];
  _okButton = [self button:@"Search" frame:NSMakeRect(342, 14, 100, 34) tag:1 in:content];
  [_okButton setKeyEquivalent:@"\r"];
  [self validate];

  [panel center];
  [panel setInitialFirstResponder:_termField];
  [panel makeFirstResponder:_termField];
  NSInteger result = [NSApp runModalForWindow:panel];
  [panel orderOut:nil];
  if (result != 1) {
    return nil;
  }
  LDSearchOptions *options = [self currentOptions];
  [preferences setLastSearchTerm:[options term]];
  [preferences setSearchUsesRegex:[options usesRegex]];
  [preferences setSearchCaseSensitive:[options caseSensitive]];
  [preferences setSearchWholePhrase:[options wholePhrase]];
  return options;
}

@end
