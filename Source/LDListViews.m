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

@implementation LDOutlineView

- (void)setCommandTarget:(id<LDListViewCommands>)target { _commandTarget = target; }

- (void)resetCursorRects
{
  [super resetCursorRects];
  LDAddLinkCursorRects(self, _commandTarget);
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

@end
