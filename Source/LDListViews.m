#import "LDListViews.h"

// Returns YES if the event was a list command.
static BOOL LDHandleListKey(NSTableView *view, id<LDListViewCommands> target, NSEvent *event)
{
  NSString *characters = [event charactersIgnoringModifiers];
  if ([characters length] != 1 || !target) {
    return NO;
  }
  unichar key = [characters characterAtIndex:0];
  if (key == NSCarriageReturnCharacter || key == NSEnterCharacter || key == NSNewlineCharacter) {
    [target listViewOpenSelection:view];
    return YES;
  }
  if (key == NSDeleteFunctionKey || key == NSDeleteCharacter) {
    [target listView:view deleteSelectionPermanently:([event modifierFlags] & NSShiftKeyMask) != 0];
    return YES;
  }
  return NO;
}

static NSMenu *LDContextMenu(NSTableView *view, id<LDListViewCommands> target, NSEvent *event)
{
  NSInteger row = [view rowAtPoint:[view convertPoint:[event locationInWindow] fromView:nil]];
  if (row < 0 || !target) {
    return nil;
  }
  if (![view isRowSelected:row]) {
    [view selectRow:row byExtendingSelection:NO];
  }
  [[view window] makeFirstResponder:view];
  return [target contextMenuForListView:view];
}

#if defined(__APPLE__)
// VoiceOver's "show menu" (and other accessibility clients) for a list whose
// menu comes from -menuForEvent:: the context menu of the selected row (the
// first visible one when nothing is selected), at that row. The menu opens
// after the action returns, as for a right click.
static BOOL LDShowContextMenuForAccessibility(NSTableView *view, id<LDListViewCommands> target)
{
  NSInteger row = [view selectedRow];
  if (row < 0) {
    row = [view rowsInRect:[view visibleRect]].location;
  }
  if (row < 0 || row >= [view numberOfRows] || !target || ![view window]) {
    return NO;
  }
  NSRect rect = [view rectOfRow:row];
  NSPoint point = [view convertPoint:NSMakePoint(NSMinX([view visibleRect]) + 24.0, NSMidY(rect)) toView:nil];
  NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0
                                     timestamp:[[NSProcessInfo processInfo] systemUptime]
                                  windowNumber:[[view window] windowNumber] context:nil
                                   eventNumber:0 clickCount:1 pressure:1.0];
  NSMenu *menu = LDContextMenu(view, target, event);
  if (!menu) {
    return NO;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
  });
  return YES;
}
#endif

static void LDAddLinkCursorRects(NSTableView *view, id<LDListViewCommands> target)
{
  if (![(id)target respondsToSelector:@selector(listView:hasLinkAtRow:column:)]) {
    return;
  }
  NSRect visible = [view visibleRect];
  NSRange rows = [view rowsInRect:visible];
  NSIndexSet *columns = [view columnIndexesInRect:visible];
  NSUInteger row = 0;
  for (row = rows.location; row < NSMaxRange(rows); row++) {
    NSUInteger column = [columns firstIndex];
    while (column != NSNotFound) {
      if ([target listView:view hasLinkAtRow:(NSInteger)row column:(NSInteger)column]) {
        NSRect cell = NSIntersectionRect([view frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row], visible);
        [view addCursorRect:cell cursor:[NSCursor pointingHandCursor]];
      }
      column = [columns indexGreaterThanIndex:column];
    }
  }
}

// libs-gui does not ask the delegate for cell tooltips, so each visible row
// gets a tooltip rect whose text comes from the row under the pointer when
// it shows, which stays right after a scroll moved the rows.
static void LDAddToolTipRects(NSTableView *view, id<LDListViewCommands> target)
{
  [view removeAllToolTips];
  if (![(id)target respondsToSelector:@selector(listView:toolTipAtRow:column:)]) {
    return;
  }
  NSRect visible = [view visibleRect];
  NSRange rows = [view rowsInRect:visible];
  NSUInteger row = 0;
  for (row = rows.location; row < NSMaxRange(rows); row++) {
    [view addToolTipRect:NSIntersectionRect([view rectOfRow:(NSInteger)row], visible) owner:view userData:NULL];
  }
}

static NSString *LDToolTipAtPoint(NSTableView *view, id<LDListViewCommands> target, NSPoint point)
{
  NSInteger row = [view rowAtPoint:point];
  NSInteger column = [view columnAtPoint:point];
  if (row < 0 || column < 0 || ![(id)target respondsToSelector:@selector(listView:toolTipAtRow:column:)]) {
    return nil;
  }
  return [target listView:view toolTipAtRow:row column:column];
}

@implementation LDOutlineView

- (void)setCommandTarget:(id<LDListViewCommands>)target { _commandTarget = target; }

- (void)resetCursorRects
{
  [super resetCursorRects];
  LDAddLinkCursorRects(self, _commandTarget);
  LDAddToolTipRects(self, _commandTarget);
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
  return LDToolTipAtPoint(self, _commandTarget, point);
}

- (void)reloadData
{
  [super reloadData];
  [[self window] invalidateCursorRectsForView:self];
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  NSInteger row = [self rowAtPoint:point];
  NSInteger column = [self columnAtPoint:point];
  id target = _commandTarget;
  BOOL follows = row >= 0 && column >= 0 && [event clickCount] == 1
    && [target respondsToSelector:@selector(listView:hasLinkAtRow:column:)]
    && [target listView:self hasLinkAtRow:row column:column];
  [super mouseDown:event];
  if (follows) {
    [target listView:self followLinkAtRow:row column:column];
  }
}

- (void)keyDown:(NSEvent *)event
{
  if (!LDHandleListKey(self, _commandTarget, event)) {
    [super keyDown:event];
  }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  return LDContextMenu(self, _commandTarget, event);
}

#if defined(__APPLE__)
- (BOOL)accessibilityPerformShowMenu
{
  return LDShowContextMenuForAccessibility(self, _commandTarget) || [super accessibilityPerformShowMenu];
}
#endif

@end

@implementation LDTableView

- (void)setCommandTarget:(id<LDListViewCommands>)target { _commandTarget = target; }

- (void)keyDown:(NSEvent *)event
{
  if (!LDHandleListKey(self, _commandTarget, event)) {
    [super keyDown:event];
  }
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  return LDContextMenu(self, _commandTarget, event);
}

#if defined(__APPLE__)
- (BOOL)accessibilityPerformShowMenu
{
  return LDShowContextMenuForAccessibility(self, _commandTarget) || [super accessibilityPerformShowMenu];
}
#endif

@end
