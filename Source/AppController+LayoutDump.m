#import "AppController.h"
#import "AppController+Private.h"
#import "LDDuplicateFinder.h"
#import "LDLayoutDump.h"
#import "LDTreemapView.h"

static const NSTimeInterval LDLayoutDumpInterval = 0.25;

static NSString *LDLayoutDumpPath = nil;
static NSData *LDLayoutDumpLast = nil;
static NSUInteger LDLayoutDumpSequence = 0;

// LINDIRSTAT_DUMP_LAYOUT=path: the full-window GUI parity gate
// (scripts/gui-parity-gate.sh) reads the window's geometry, columns, tabs,
// treemap cells and state from this file instead of guessing from pixels.
// It is rewritten whenever any of that changes. Without the variable nothing
// is scheduled.
@implementation AppController (LayoutDump)

- (void)startLayoutDumpIfRequested
{
  LDLayoutDumpPath = [LDLayoutDump requestedPathInEnvironment:[[NSProcessInfo processInfo] environment]];
  if (!LDLayoutDumpPath) {
    return;
  }
  [LDLayoutDump startTrackingMenus];
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:LDLayoutDumpInterval
                                                    target:self
                                                  selector:@selector(layoutDumpTimerFired:)
                                                  userInfo:nil
                                                   repeats:YES];
  // Keep dumping while menus and panels track events.
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
}

- (void)layoutDumpTimerFired:(NSTimer *)timer
{
  (void)timer;
  NSMutableDictionary *layout = [self layoutDescription];
  NSData *data = [NSJSONSerialization dataWithJSONObject:layout options:0 error:NULL];
  if (!data || [data isEqualToData:LDLayoutDumpLast]) {
    return;
  }
  LDLayoutDumpLast = data;
  [layout setObject:@(++LDLayoutDumpSequence) forKey:@"sequence"];
  [LDLayoutDump writeJSONObject:layout toPath:LDLayoutDumpPath];
}

- (NSMapTable *)layoutRoles
{
  NSMapTable *roles = [NSMapTable strongToStrongObjectsMapTable];
  NSDictionary *views = @{
    @"mainSplit": _mainSplit, @"topSplit": _topSplit, @"fileTabs": _fileTabs,
    @"extensionPane": _extensionScroll, @"treemap": _treemapView,
    @"statusField": _statusField, @"selectionField": _selectionField, @"memoryField": _memoryField,
    @"directoryTable": _directoryTable, @"extensionTable": _extensionTable,
    @"largestTable": _largestTable, @"duplicatesTable": _duplicatesTable,
    @"searchTable": _searchTable, @"watcherTable": _watcherTable,
  };
  for (NSString *role in views) {
    [roles setObject:role forKey:[views objectForKey:role]];
  }
  return roles;
}

- (NSString *)layoutLabelOfRow:(NSInteger)row inTable:(NSTableView *)table
{
  id value = nil;
  if ([table isKindOfClass:[NSOutlineView class]]) {
    id item = [(NSOutlineView *)table itemAtRow:row];
    if ([item isKindOfClass:[LDFileNode class]]) {
      return [item path];
    }
    if ([item isKindOfClass:[LDDuplicateGroup class]]) {
      return [item hashString];
    }
    value = item;
  } else {
    NSTableColumn *first = [[table tableColumns] firstObject];
    value = [(id<NSTableViewDataSource>)[table dataSource] tableView:table objectValueForTableColumn:first row:row];
  }
  if ([value isKindOfClass:[NSAttributedString class]]) {
    return [value string];
  }
  return [value isKindOfClass:[NSString class]] ? value : [value description];
}

- (NSDictionary *)layoutTables
{
  NSDictionary *tables = @{
    @"directoryTable": _directoryTable, @"extensionTable": _extensionTable,
    @"largestTable": _largestTable, @"duplicatesTable": _duplicatesTable,
    @"searchTable": _searchTable, @"watcherTable": _watcherTable,
  };
  NSMutableDictionary *described = [NSMutableDictionary dictionary];
  for (NSString *role in tables) {
    NSTableView *table = [tables objectForKey:role];
    // Tables in hidden tabs or hidden panes are not in the window.
    if (![table window] || [table isHiddenOrHasHiddenAncestor]) {
      continue;
    }
    [described setObject:[LDLayoutDump describeTable:table rowLabels:^NSString *(NSInteger row) {
      return [self layoutLabelOfRow:row inTable:table];
    }] forKey:role];
  }
  return described;
}

- (NSArray *)layoutRectOfCell:(NSInteger)index inTreemap:(LDTreemap *)treemap area:(NSRect)area
{
  LDTreemapRect rect = [treemap rectOfCell:(NSUInteger)index];
  NSRect viewRect = NSMakeRect(NSMinX(area) + rect.left, NSMinY(area) + rect.top,
                               LDTreemapRectWidth(rect), LDTreemapRectHeight(rect));
  return [LDLayoutDump rect:viewRect ofView:_treemapView] ?: @[];
}

- (NSDictionary *)layoutTreemap
{
  LDTreemap *treemap = [_treemapView treemap];
  NSRect area = [_treemapView treemapArea];
  NSMutableArray *leaves = [NSMutableArray array];
  [treemap enumerateRenderedCellsUsingBlock:^(NSUInteger index, NSUInteger depth) {
    [leaves addObject:@{@"path": [[treemap nodeOfCell:index] path] ?: @"",
                        @"depth": @(depth),
                        @"rect": [self layoutRectOfCell:(NSInteger)index inTreemap:treemap area:area]}];
  }];
  NSMutableDictionary *description = [NSMutableDictionary dictionaryWithDictionary:@{
    @"rect": [LDLayoutDump rectOfView:_treemapView] ?: @[],
    @"area": [LDLayoutDump rect:area ofView:_treemapView] ?: @[],
    @"renderSize": treemap ? @[@([treemap width]), @([treemap height])] : @[],
    @"leafCount": @([leaves count]),
    @"leaves": leaves,
    @"zoomed": @([_treemapView isZoomed]),
    @"highlightedExtension": [_treemapView highlightedExtensionKey] ?: @"",
  }];
  LDFileNode *selected = [_treemapView selectedNode];
  NSInteger cell = selected && treemap ? [treemap cellIndexForNode:selected] : -1;
  if (cell >= 0) {
    [description setObject:@{@"path": [selected path] ?: @"",
                             @"rect": [self layoutRectOfCell:cell inTreemap:treemap area:area]}
                    forKey:@"selected"];
  }
  return description;
}

- (NSMutableDictionary *)layoutDescription
{
  NSMutableArray *selected = [NSMutableArray array];
  for (LDFileNode *node in [self selectedNodes]) {
    [selected addObject:[node path] ?: @""];
  }
  NSRect screen = [[_window screen] ?: [NSScreen mainScreen] frame];
  return [NSMutableDictionary dictionaryWithDictionary:@{
    @"state": @{
      @"scanning": @([self isScanning]),
      @"busy": @([self isBusy]),
      @"findingDuplicates": @([self isFindingDuplicates]),
      @"root": [_rootNode path] ?: @"",
      @"selectedNodes": selected,
      @"activeList": [[self layoutRoles] objectForKey:[self activeFileList]] ?: @"",
    },
    @"screen": [LDLayoutDump arrayForScreenRect:screen screenHeight:NSMaxY(screen)],
    @"mainMenu": [LDLayoutDump titlesOfMenu:[NSApp mainMenu]],
    @"tabs": [LDLayoutDump describeTabView:_fileTabs],
    @"tables": [self layoutTables],
    @"treemap": [self layoutTreemap],
    @"windows": [LDLayoutDump describeWindowsWithRoles:[self layoutRoles]],
    @"openMenus": [LDLayoutDump openMenus],
  }];
}

@end
