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

@implementation LDOutlineView

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
