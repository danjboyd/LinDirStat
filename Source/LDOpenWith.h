#import <AppKit/AppKit.h>

// "Open With", in place of WinDirStat's "Windows Explorer Menu" (the shell's
// context menu, MainFrame.cpp OnInitMenuPopup): the applications that can
// open a selection, and opening it with one. Linux reads freedesktop.org
// desktop entries and mimeapps.list (LDDesktopEntry, LDMimeApps); macOS
// asks NSWorkspace.

@interface LDOpenWithApplication : NSObject
{
  NSString *_identifier;
  NSString *_name;
  NSImage *_icon;
  BOOL _default;
  id _platformObject;
}

+ (LDOpenWithApplication *)applicationWithIdentifier:(NSString *)identifier
                                                name:(NSString *)name
                                                icon:(NSImage *)icon
                                           isDefault:(BOOL)isDefault
                                      platformObject:(id)platformObject;
// Desktop file ID on Linux ("org.gnome.TextEditor.desktop"), bundle
// identifier or application URL on macOS.
- (NSString *)identifier;
- (NSString *)name;
// A menu-sized icon when it is cheap to get, else nil.
- (NSImage *)icon;
// The selection's default application.
- (BOOL)isDefault;
// The backend's own record (LDDesktopEntry, NSURL...).
- (id)platformObject;

@end

@interface LDOpenWith : NSObject

+ (LDOpenWith *)sharedOpenWith;

// Applications that can open every path (exact bytes), the default
// application first and then the rest by name. Empty when paths is empty
// or nothing fits.
- (NSArray *)applicationsForPaths:(NSArray *)paths;

// Starts application with paths without waiting for it. Returns NO when it
// could not be started.
- (BOOL)openPaths:(NSArray *)paths withApplication:(LDOpenWithApplication *)application;

@end
