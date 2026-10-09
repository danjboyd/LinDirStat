#import <Foundation/Foundation.h>

// Where keyboard focus can be: a file tab (its position among the visible
// tabs, 0 being All Files), the extension list, or anything else (the
// treemap).
enum {
  LDFocusExtensionList = -1,
  LDFocusOther = -2
};

// WinDirStat's Tab order (FileTabbedView.cpp CycleTab, ExtensionListControl
// and the dead-focus window): Tab walks the visible file tabs left to right
// and then the extension list, which leads back to All Files; Shift+Tab
// walks the other way. Without an extension list it wraps among the tabs.
@interface LDTabCycle : NSObject

// The next focus target: a tab position or LDFocusExtensionList.
+ (NSInteger)nextFocusFrom:(NSInteger)current
               visibleTabs:(NSUInteger)tabCount
     extensionListVisible:(BOOL)extensionListVisible
                   forward:(BOOL)forward;

@end
