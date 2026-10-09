#import "LDLayoutDump.h"

// Rows described per table; enough to click and to check what is shown.
static const NSInteger LDLayoutDumpMaxRows = 40;

@implementation LDLayoutDump

+ (NSString *)requestedPathInEnvironment:(NSDictionary *)environment
{
  NSString *path = [environment objectForKey:@"LINDIRSTAT_DUMP_LAYOUT"];
  return [path length] > 0 ? path : nil;
}

+ (NSArray *)arrayForScreenRect:(NSRect)rect screenHeight:(CGFloat)screenHeight
{
  // Edges are rounded, not sizes, so adjacent views stay adjacent.
  CGFloat left = round(NSMinX(rect));
  CGFloat right = round(NSMaxX(rect));
  CGFloat top = round(screenHeight - NSMaxY(rect));
  CGFloat bottom = round(screenHeight - NSMinY(rect));
  return @[@(left), @(top), @(right - left), @(bottom - top)];
}

+ (NSArray *)runsOfSamples:(NSArray *)samples start:(CGFloat)start step:(CGFloat)step
{
  NSMutableArray *runs = [NSMutableArray array];
  NSMutableDictionary *run = nil;
  for (NSUInteger i = 0; i < [samples count]; i++) {
    id item = [samples objectAtIndex:i];
    CGFloat x = start + step * i;
    if (run && [run objectForKey:@"item"] == item) {
      [run setObject:@(x) forKey:@"end"];
      continue;
    }
    run = nil;
    if (item != [NSNull null]) {
      run = [NSMutableDictionary dictionaryWithDictionary:@{@"item": item, @"start": @(x), @"end": @(x)}];
      [runs addObject:run];
    }
  }
  return runs;
}

+ (CGFloat)screenHeightOfWindow:(NSWindow *)window
{
  NSScreen *screen = [window screen] ?: [NSScreen mainScreen];
  return NSMaxY([screen frame]);
}

+ (NSArray *)rect:(NSRect)rect ofView:(NSView *)view
{
  NSWindow *window = [view window];
  if (!window) {
    return nil;
  }
  NSRect screenRect = [window convertRectToScreen:[view convertRect:rect toView:nil]];
  return [self arrayForScreenRect:screenRect screenHeight:[self screenHeightOfWindow:window]];
}

+ (NSArray *)rectOfView:(NSView *)view
{
  return [self rect:[view bounds] ofView:view];
}

+ (NSString *)stringValueOfView:(NSView *)view
{
  if ([view isKindOfClass:[NSTextField class]]) {
    return [(NSTextField *)view stringValue];
  }
  if ([view isKindOfClass:[NSButton class]]) {
    return [(NSButton *)view title];
  }
  return nil;
}

// YES when the view's edges do not fall on whole window pixels.
+ (BOOL)isOffPixelGrid:(NSView *)view
{
  NSRect rect = [view convertRect:[view bounds] toView:nil];
  CGFloat edges[4] = {NSMinX(rect), NSMinY(rect), NSMaxX(rect), NSMaxY(rect)};
  for (NSUInteger i = 0; i < 4; i++) {
    if (fabs(edges[i] - round(edges[i])) > 0.01) {
      return YES;
    }
  }
  return NO;
}

// GNUstep draws menus (the in-window menu bar, pop-ups) with NSMenuView,
// whose -menu is the menu it shows. Apple has no such view.
+ (BOOL)isMenuView:(NSView *)view
{
  Class menuViewClass = NSClassFromString(@"NSMenuView");
  return menuViewClass && [view isKindOfClass:menuViewClass];
}

+ (NSDictionary *)describeViewTree:(NSView *)view roles:(NSMapTable *)roles
{
  NSMutableDictionary *description = [NSMutableDictionary dictionary];
  [description setObject:NSStringFromClass([view class]) forKey:@"class"];
  [description setObject:[self rectOfView:view] ?: @[] forKey:@"rect"];
  if ([self isOffPixelGrid:view]) {
    [description setObject:@YES forKey:@"subpixel"];
  }
  NSString *role = [roles objectForKey:view];
  if (role) {
    [description setObject:role forKey:@"role"];
  }
  NSString *text = [self stringValueOfView:view];
  if ([text length] > 0) {
    [description setObject:text forKey:@"text"];
  }
  if ([self isMenuView:view]) {
    [description setObject:[self titlesOfMenu:[view menu]] forKey:@"menuItems"];
  }
  NSMutableArray *children = [NSMutableArray array];
  for (NSView *subview in [view subviews]) {
    if (![subview isHidden]) {
      [children addObject:[self describeViewTree:subview roles:roles]];
    }
  }
  if ([children count] > 0) {
    [description setObject:children forKey:@"children"];
  }
  return description;
}

+ (NSDictionary *)describeColumn:(NSTableColumn *)column index:(NSInteger)index ofTable:(NSTableView *)table
{
  NSCell *cell = [column headerCell];
  NSRect header = [[table headerView] headerRectOfColumn:index];
  NSRect titleRect = [cell titleRectForBounds:header];
  return @{
    @"id": [column identifier] ?: @"",
    @"title": [cell stringValue] ?: @"",
    @"width": @([column width]),
    @"rect": [self rect:header ofView:[table headerView]] ?: @[],
    @"titleWidth": @(ceil([[cell attributedStringValue] size].width)),
    @"titleAreaWidth": @(floor(NSWidth(titleRect))),
    @"alignment": [cell alignment] == NSRightTextAlignment ? @"right"
                  : ([cell alignment] == NSCenterTextAlignment ? @"center" : @"left"),
  };
}

+ (NSDictionary *)describeTable:(NSTableView *)table rowLabels:(NSString *(^)(NSInteger row))labels
{
  NSMutableArray *columns = [NSMutableArray array];
  NSArray *tableColumns = [table tableColumns];
  for (NSUInteger i = 0; i < [tableColumns count]; i++) {
    [columns addObject:[self describeColumn:[tableColumns objectAtIndex:i] index:(NSInteger)i ofTable:table]];
  }
  NSMutableArray *rows = [NSMutableArray array];
  NSRect visible = [table visibleRect];
  NSRange range = [table rowsInRect:visible];
  for (NSInteger row = (NSInteger)range.location;
       row < (NSInteger)NSMaxRange(range) && [rows count] < (NSUInteger)LDLayoutDumpMaxRows; row++) {
    NSRect rowRect = NSIntersectionRect([table rectOfRow:row], visible);
    [rows addObject:@{@"row": @(row),
                      @"rect": [self rect:rowRect ofView:table] ?: @[],
                      @"label": (labels ? labels(row) : nil) ?: @""}];
  }
  NSMutableArray *selected = [NSMutableArray array];
  NSIndexSet *selection = [table selectedRowIndexes];
  for (NSUInteger row = [selection firstIndex]; row != NSNotFound; row = [selection indexGreaterThanIndex:row]) {
    [selected addObject:@(row)];
  }
  return @{
    @"rect": [self rectOfView:[table enclosingScrollView] ?: table] ?: @[],
    @"headerRect": [self rectOfView:[table headerView]] ?: @[],
    @"columns": columns,
    @"rowCount": @([table numberOfRows]),
    @"rows": rows,
    @"selectedRows": selected,
  };
}

+ (NSDictionary *)describeTabView:(NSTabView *)tabView
{
  NSRect bounds = [tabView bounds];
  NSRect content = [tabView contentRect];
  // The strip is the band outside the content area, above or below it.
  CGFloat lowGap = NSMinY(content) - NSMinY(bounds);
  CGFloat highGap = NSMaxY(bounds) - NSMaxY(content);
  CGFloat y = lowGap > highGap ? NSMinY(bounds) + lowGap / 2.0 : NSMaxY(content) + highGap / 2.0;
  NSMutableArray *samples = [NSMutableArray array];
  for (CGFloat x = NSMinX(bounds); x < NSMaxX(bounds); x += 1.0) {
    NSPoint point = [tabView convertPoint:NSMakePoint(x, y) toView:[tabView superview]];
    [samples addObject:[tabView tabViewItemAtPoint:point] ?: (id)[NSNull null]];
  }
  CGFloat stripHeight = MAX(lowGap, highGap);
  NSMutableArray *tabs = [NSMutableArray array];
  for (NSDictionary *run in [self runsOfSamples:samples start:NSMinX(bounds) step:1.0]) {
    NSTabViewItem *item = [run objectForKey:@"item"];
    CGFloat start = [[run objectForKey:@"start"] doubleValue];
    CGFloat end = [[run objectForKey:@"end"] doubleValue] + 1.0;
    NSRect tabRect = NSMakeRect(start, y - stripHeight / 2.0, end - start, stripHeight);
    [tabs addObject:@{@"id": [item identifier] ?: @"", @"label": [item label] ?: @"",
                      @"rect": [self rect:tabRect ofView:tabView] ?: @[]}];
  }
  return @{
    @"rect": [self rectOfView:tabView] ?: @[],
    @"contentRect": [self rect:content ofView:tabView] ?: @[],
    @"selected": [[tabView selectedTabViewItem] identifier] ?: @"",
    @"tabs": tabs,
  };
}

static NSMutableArray *LDTrackedMenus = nil;

+ (void)startTrackingMenus
{
  if (LDTrackedMenus) {
    return;
  }
  LDTrackedMenus = [NSMutableArray array];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
    [LDTrackedMenus removeObjectIdenticalTo:[note object]];
    [LDTrackedMenus addObject:[note object]];
  }];
  [center addObserverForName:NSMenuDidEndTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
    [LDTrackedMenus removeObjectIdenticalTo:[note object]];
  }];
}

+ (NSArray *)openMenus
{
  NSMutableArray *menus = [NSMutableArray array];
  for (NSMenu *menu in LDTrackedMenus) {
    [menus addObject:@{@"items": [self titlesOfMenu:menu], @"mainMenu": @(menu == [NSApp mainMenu])}];
  }
  return menus;
}

+ (NSArray *)titlesOfMenu:(NSMenu *)menu
{
  NSMutableArray *titles = [NSMutableArray array];
  for (NSMenuItem *item in [menu itemArray]) {
    [titles addObject:[item isSeparatorItem] ? @"-" : ([item title] ?: @"")];
  }
  return titles;
}

+ (NSArray *)describeWindowsWithRoles:(NSMapTable *)roles
{
  NSMutableArray *windows = [NSMutableArray array];
  for (NSWindow *window in [NSApp windows]) {
    if (![window isVisible]) {
      continue;
    }
    NSView *root = [[window contentView] superview] ?: [window contentView];
    NSRect frame = [window frame];
    NSToolbar *toolbar = [window toolbar];
    NSMutableDictionary *description = [NSMutableDictionary dictionaryWithDictionary:@{
      @"class": NSStringFromClass([window class]),
      @"title": [window title] ?: @"",
      @"rect": [self arrayForScreenRect:frame screenHeight:[self screenHeightOfWindow:window]],
      @"content": [self rectOfView:[window contentView]] ?: @[],
      @"key": @([window isKeyWindow]),
      @"main": @([window isMainWindow]),
      @"views": [self describeViewTree:root roles:roles],
    }];
    if (toolbar) {
      NSMutableArray *items = [NSMutableArray array];
      for (NSToolbarItem *item in [toolbar items]) {
        [items addObject:@{@"id": [item itemIdentifier] ?: @"", @"label": [item label] ?: @""}];
      }
      [description setObject:@{@"visible": @([toolbar isVisible]), @"items": items} forKey:@"toolbar"];
    }
    [windows addObject:description];
  }
  return windows;
}

+ (BOOL)writeJSONObject:(id)object toPath:(NSString *)path
{
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:NULL];
  return data && [data writeToFile:path atomically:YES];
}

+ (BOOL)writeJSONObject:(id)object
                 toPath:(NSString *)path
       replacingString:(NSString *)token
               withJSON:(NSData *)json
{
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:NULL];
  if (!data) {
    return NO;
  }
  NSData *quoted = [[NSString stringWithFormat:@"\"%@\"", token] dataUsingEncoding:NSUTF8StringEncoding];
  NSRange range = [data rangeOfData:quoted options:0 range:NSMakeRange(0, [data length])];
  if (range.location == NSNotFound || !json) {
    return [data writeToFile:path atomically:YES];
  }
  NSMutableData *spliced = [data mutableCopy];
  [spliced replaceBytesInRange:range withBytes:[json bytes] length:[json length]];
  return [spliced writeToFile:path atomically:YES];
}

@end
