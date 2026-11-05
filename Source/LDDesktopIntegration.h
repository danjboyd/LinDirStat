#import <Foundation/Foundation.h>

@class LDPreferences;

// Puts an AppImage on the desktop: GNOME Shell shows an app's icon only for a
// window that matches an installed desktop entry, and a bare AppImage installs
// none (#157). Used on Linux only; on macOS nothing here runs.
typedef enum {
  LDDesktopIntegrationUnavailable = 0,  // not running from an AppImage
  LDDesktopIntegrationNotInstalled,
  LDDesktopIntegrationInstalled,        // our entry, for this AppImage
  LDDesktopIntegrationMoved,            // our entry, for another path
  LDDesktopIntegrationExternal          // someone else's entry for LinDirStat
} LDDesktopIntegrationState;

@interface LDDesktopIntegration : NSObject

// environment gives APPIMAGE, APPDIR and the XDG locations (LDMimeApps).
+ (LDDesktopIntegration *)integrationForEnvironment:(NSDictionary *)environment;

- (LDDesktopIntegrationState)state;
// Writes (or rewrites) our entry and the icon.
- (BOOL)install:(NSError **)error;
// Removes our entry and the icon. Someone else's entry is left alone.
- (BOOL)remove:(NSError **)error;
- (NSString *)entryPath;
- (NSString *)iconPath;
// The desktop entry's text for this AppImage.
- (NSString *)entryText;

// Whether the prompt may show: not after Don't Ask Again, nor within 7 days of
// Not Now.
+ (BOOL)mayOfferWithPreferences:(LDPreferences *)preferences now:(NSDate *)now;

// At launch: moves our entry to this AppImage if it was moved, and asks once
// if nothing lists LinDirStat. Later calls do nothing. Does nothing on macOS,
// or with LINDIRSTAT_DESKTOP_PROMPT=off (the release checks) except the move.
+ (void)offerAfterLaunch;

@end
