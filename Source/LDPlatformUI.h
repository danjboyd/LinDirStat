#import <AppKit/AppKit.h>

@class LDFileNode;

// The few places where the app looks different per platform. Under GNUstep
// these keep the freedesktop symbolic icons and the menus as built; on macOS
// they use SF Symbols, Finder's file icons and the standard Mac menus.
@interface LDPlatformUI : NSObject

// Called once at launch. On macOS, LINDIRSTAT_APPEARANCE=dark or light
// forces that appearance (for GUI review screenshots).
+ (void)prepareApplication:(NSApplication *)application;

// The toolbar image for a freedesktop symbolic icon name
// ("view-refresh-symbolic"); label is its accessibility description.
+ (NSImage *)toolbarImageNamed:(NSString *)name label:(NSString *)label;
// The same image for small symbolic icons elsewhere (the tree's fallback
// icons, which the app tints): an SF Symbol on macOS, the bundled PNG under
// GNUstep.
+ (NSImage *)symbolicImageNamed:(NSString *)name;

// The file manager's icon for node at 16 points, or nil to use the app's
// own symbolic icons.
+ (NSImage *)fileIconForNode:(LDFileNode *)node;

// YES on macOS, where Control-F1…F4 belong to the system's keyboard
// navigation: Command-1…4 select the file tabs instead.
+ (BOOL)usesCommandDigitsForFileTabs;

// Platform table appearance: on macOS WinDirStat's dense lists use the full
// width style (not the padded inset one) and no focus ring around the pane.
+ (void)configureTable:(NSTableView *)table;

// "Settings" on macOS, "Preferences" elsewhere.
+ (NSString *)settingsTitle;

// "Show in Finder" on macOS, "Show in Files" elsewhere.
+ (NSString *)showInFileManagerTitle;

// YES when NSTableView's column autoresizing styles work, so the flexible
// column can be left to the table instead of being fitted by hand.
+ (BOOL)tablesAutoresizeColumns;

// After a scan of the disk (not a CSV load): on macOS, if folders were
// hidden by privacy protection and the app lacks Full Disk Access, explains
// how to grant it (once per launch, unless the user said not to ask again).
+ (void)scanDidFinishWithRoot:(LDFileNode *)root window:(NSWindow *)window;

// Finishes the main menu for the platform: on macOS the application menu
// (About, Settings, Services, Hide, Quit), a Window menu and a Help menu.
// preferencesTarget receives -showPreferences:.
+ (void)completeMainMenu:(NSMenu *)mainMenu
         applicationMenu:(NSMenu *)applicationMenu
       preferencesTarget:(id)preferencesTarget;

@end
