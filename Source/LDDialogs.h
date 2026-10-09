#import <AppKit/AppKit.h>

@class LDFileNode;

// Modal dialogs built from standard controls (the theme draws them).
@interface LDDialogs : NSObject

// A heading, a message, a scrollable list of items (paths) and buttons in
// GNOME's order (left to right, the cancelling one first). Return presses
// buttons[defaultIndex]; Escape and closing press buttons[0].
// checkboxTitle, if given, adds a checkbox whose final state is returned in
// *checked. Returns the index of the button pressed.
+ (NSInteger)runListPanelWithTitle:(NSString *)title
                           message:(NSString *)message
                             items:(NSArray *)items
                           buttons:(NSArray *)buttons
                      defaultIndex:(NSUInteger)defaultIndex
                     checkboxTitle:(NSString *)checkboxTitle
                           checked:(BOOL *)checked;

// WinDirStat's delete warning: lists every path; Cancel is the default.
// Returns YES to go ahead. *dontAskAgain reports the checkbox.
+ (BOOL)confirmDestructiveAction:(NSString *)actionTitle
                         message:(NSString *)message
                           paths:(NSArray *)paths
                    dontAskAgain:(BOOL *)dontAskAgain;

// Reports failures as "path: reason" lines.
+ (void)showFailures:(NSArray *)lines title:(NSString *)title;

// A non-modal window with an item's details (WinDirStat's Properties
// opens the shell's dialog; this is the Linux stand-in).
+ (void)showPropertiesForNode:(LDFileNode *)node;

// Selectable text in a panel (for hashes).
+ (void)showText:(NSString *)text title:(NSString *)title;

@end
