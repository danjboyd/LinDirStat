#import <AppKit/AppKit.h>

// Keyboard and context menu hooks shared by the file lists, following
// WinDirStat: Enter opens, Delete moves to the trash, Shift+Delete deletes
// permanently, and a right click selects the row under the pointer (keeping
// a multiple selection that contains it) before showing the menu.
@protocol LDListViewCommands
- (void)listViewOpenSelection:(NSTableView *)view;
- (void)listView:(NSTableView *)view deleteSelectionPermanently:(BOOL)permanently;
- (NSMenu *)contextMenuForListView:(NSTableView *)view;
@end

@interface LDOutlineView : NSOutlineView
{
  __weak id<LDListViewCommands> _commandTarget;
}
- (void)setCommandTarget:(id<LDListViewCommands>)target;
@end

@interface LDTableView : NSTableView
{
  __weak id<LDListViewCommands> _commandTarget;
}
- (void)setCommandTarget:(id<LDListViewCommands>)target;
@end
