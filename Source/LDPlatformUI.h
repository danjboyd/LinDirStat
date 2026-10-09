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

// The file manager's icon for node at 16 points, or nil to use the app's
// own symbolic icons.
+ (NSImage *)fileIconForNode:(LDFileNode *)node;

// "Settings" on macOS, "Preferences" elsewhere.
+ (NSString *)settingsTitle;

// "Show in Finder" on macOS, "Show in Files" elsewhere.
+ (NSString *)showInFileManagerTitle;

// YES when NSTableView's column autoresizing styles work, so the flexible
// column can be left to the table instead of being fitted by hand.
+ (BOOL)tablesAutoresizeColumns;

// Finishes the main menu for the platform: on macOS the application menu
// (About, Settings, Services, Hide, Quit), a Window menu and a Help menu.
// preferencesTarget receives -showPreferences:.
+ (void)completeMainMenu:(NSMenu *)mainMenu
         applicationMenu:(NSMenu *)applicationMenu
       preferencesTarget:(id)preferencesTarget;

@end
