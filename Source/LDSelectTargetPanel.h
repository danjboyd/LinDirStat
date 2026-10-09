#import <AppKit/AppKit.h>

// WinDirStat's Select Drives dialog ("Select Target"): all local drives,
// individual drives from a list with their usage, or one folder.
@interface LDSelectTargetPanel : NSObject

// Runs the dialog modally. Returns the paths to scan (one folder, one or
// more mount points), or nil if cancelled. On OK it stores the mode, the
// selected drives, the folder history (addFolderToHistory:) and the
// duplicates checkbox in LDPreferences.
+ (NSArray *)runWithInitialFolder:(NSString *)folder;

@end
