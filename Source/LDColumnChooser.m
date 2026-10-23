#import "LDColumnChooser.h"
#import "LDPreferences.h"

@implementation LDColumnChooser

- (instancetype)initWithTable:(NSTableView *)table
                         list:(NSString *)list
              requiredColumns:(NSArray *)identifiers
                  preferences:(LDPreferences *)preferences
{
  self = [super init];
  if (self) {
    _table = table;
    _list = [list copy];
    _preferences = preferences;
    _columns = [[table tableColumns] copy];
    NSMutableSet *required = [NSMutableSet setWithArray:identifiers ?: @[]];
    // OnColumnsInserted: the first column can never be hidden.
    if ([_columns count] > 0) {
      [required addObject:[[_columns objectAtIndex:0] identifier]];
    }
    _required = required;
    _menu = [[NSMenu alloc] initWithTitle:@""];
    [_menu setAutoenablesItems:NO];
    // GNUstep's NSMenuDelegate lists optional methods as required.
    [_menu setDelegate:(id<NSMenuDelegate>)self];
    [[table headerView] setMenu:_menu];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(preferencesDidChange:)
                                                 name:LDPreferencesDidChangeNotification
                                               object:preferences];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)invalidate
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _changeHandler = nil;
  _table = nil;
}

- (NSString *)list { return _list; }
- (NSMenu *)menu { return _menu; }
- (void)setChangeHandler:(void (^)(void))handler { _changeHandler = [handler copy]; }

- (BOOL)isColumnRequired:(NSString *)identifier
{
  return [_required containsObject:identifier];
}

- (BOOL)isColumnShown:(NSString *)identifier
{
  return [self isColumnRequired:identifier] || [_preferences isColumn:identifier shownInList:_list];
}

- (void)preferencesDidChange:(NSNotification *)notification
{
  (void)notification;
  [self applyPreferences];
}

#pragma mark - Menu

// ShowColumnContextMenu: every column, in the list's order.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
  while ([menu numberOfItems] > 0) {
    [menu removeItemAtIndex:0];
  }
  for (NSTableColumn *column in _columns) {
    NSString *identifier = [column identifier];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[[column headerCell] stringValue] ?: identifier
                                                  action:@selector(columnItemChosen:)
                                           keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:identifier];
    [item setState:[self isColumnShown:identifier] ? NSOnState : NSOffState];
    [item setEnabled:![self isColumnRequired:identifier]];
    [menu addItem:item];
  }
}

- (void)columnItemChosen:(id)sender
{
  [self toggleColumn:[sender representedObject]];
}

- (void)toggleColumn:(NSString *)identifier
{
  if (!identifier || [self isColumnRequired:identifier]) {
    return;
  }
  [_preferences setColumn:identifier shown:![self isColumnShown:identifier] inList:_list];
}

#pragma mark - Applying

- (BOOL)isPresent:(NSTableColumn *)column
{
  return [[_table tableColumns] indexOfObjectIdenticalTo:column] != NSNotFound;
}

// After the nearest earlier column that is shown, wherever the user has
// dragged it.
- (void)insertColumn:(NSTableColumn *)column
{
  NSInteger index = 0;
  NSUInteger position = [_columns indexOfObjectIdenticalTo:column];
  for (NSUInteger i = position; i > 0; i--) {
    NSUInteger found = [[_table tableColumns] indexOfObjectIdenticalTo:[_columns objectAtIndex:i - 1]];
    if (found != NSNotFound) {
      index = (NSInteger)found + 1;
      break;
    }
  }
  [_table addTableColumn:column];
  NSInteger last = [_table numberOfColumns] - 1;
  if (index < last) {
    [_table moveColumn:last toColumn:index];
  }
}

// SetColumnVisible's sorting fallback.
- (void)stopSortingByColumn:(NSString *)identifier
{
  NSArray *descriptors = [_table sortDescriptors];
  if ([descriptors count] == 0) {
    return;
  }
  NSArray *sorted;
  if ([[[descriptors objectAtIndex:0] key] isEqualToString:identifier]) {
    NSSortDescriptor *first = [[_columns objectAtIndex:0] sortDescriptorPrototype];
    sorted = first ? @[first] : @[];
  } else {
    NSPredicate *others = [NSPredicate predicateWithBlock:^BOOL(NSSortDescriptor *descriptor, NSDictionary *bindings) {
      (void)bindings;
      return ![[descriptor key] isEqualToString:identifier];
    }];
    sorted = [descriptors filteredArrayUsingPredicate:others];
  }
  if (![sorted isEqualToArray:descriptors]) {
    [_table setSortDescriptors:sorted];
  }
}

- (BOOL)applyPreferences
{
  NSTableView *table = _table;
  if (!table) {
    return NO;
  }
  BOOL changed = NO;
  for (NSTableColumn *column in _columns) {
    BOOL shown = [self isColumnShown:[column identifier]];
    if (shown == [self isPresent:column]) {
      continue;
    }
    changed = YES;
    if (shown) {
      [self insertColumn:column];
    } else {
      [table removeTableColumn:column];
    }
  }
  // Also when the list was sorted by a hidden column before (its default
  // sort, at launch: OnColumnsInserted).
  for (NSTableColumn *column in _columns) {
    if (![self isPresent:column]) {
      [self stopSortingByColumn:[column identifier]];
    }
  }
  if (changed && _changeHandler) {
    _changeHandler();
  }
  return changed;
}

@end
