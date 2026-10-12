#import <AppKit/AppKit.h>

// The in-app updater: gnustep-packager's (vendor/gnustep-packager-updater),
// for the AppImage. It is on only when the update configuration packaging
// puts next to the app is there, so a build run from the tree never updates
// itself. The macOS build has no updater (packagedUpdates is nil).
@interface LDUpdates : NSObject

// The updater for this copy of the app, or nil when it has no packaged
// update configuration (or no updater).
+ (instancetype)packagedUpdates;

// An updater for a configuration read from path (the packaged
// configuration's format), or nil when it cannot be read. For tests.
+ (instancetype)updatesWithConfigurationFile:(NSString *)path error:(NSError **)error;

// The version this copy is, as the configuration says.
- (NSString *)currentVersion;

// Starts the automatic checks (quiet when there is no update); dialogs
// attach to window.
- (void)startWithWindow:(NSWindow *)window;

// Help > Check for Updates…: always reports, up to date or not.
- (void)checkForUpdates:(id)sender;

// The newest version the feed offers when it is newer than this copy (and
// not skipped), nil when this copy is current. For tests and diagnostics;
// blocks while the feed downloads.
- (NSString *)newerVersionFromFeedWithError:(NSError **)error;

@end
