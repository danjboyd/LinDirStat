#import <AppKit/AppKit.h>

@class LDPreferences;

// WinDirStat 2.6's list-header column chooser (WdsListControl.cpp,
// db7af300): a right click on a list's header shows a menu of its columns,
// checked when shown. Required columns (always the first) are greyed out.
// Visibility is a per-list preference, so the menu, Preferences and the list
// stay in step: the chooser adds and removes the table's columns whenever
// the preferences change, keeping each column in its place among the others.
// A list is never sorted by a hidden column: hiding the column it is sorted
// by sorts it by the first column, and a hidden secondary sort column is
// dropped.
@interface LDColumnChooser : NSObject
{
  __weak NSTableView *_table;
  NSString *_list;
  LDPreferences *_preferences;
  NSArray *_columns;
  NSSet *_required;
  NSMenu *_menu;
  void (^_changeHandler)(void);
}

// The table's columns as they are now are the ones it can show, in order.
- (instancetype)initWithTable:(NSTableView *)table
                         list:(NSString *)list
              requiredColumns:(NSArray *)identifiers
                  preferences:(LDPreferences *)preferences;
- (NSString *)list;
- (NSMenu *)menu;
- (BOOL)isColumnRequired:(NSString *)identifier;
// Called after the chooser has added or removed columns.
- (void)setChangeHandler:(void (^)(void))handler;
// Adds and removes columns to match the preferences; YES if any changed.
// The chooser also does this itself when the preferences change.
- (BOOL)applyPreferences;
// What choosing a column's menu item does.
- (void)toggleColumn:(NSString *)identifier;
// Stops following the preferences.
- (void)invalidate;
@end
