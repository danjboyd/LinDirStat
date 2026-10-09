#import "LDOpenWith.h"

@implementation LDOpenWithApplication

+ (LDOpenWithApplication *)applicationWithIdentifier:(NSString *)identifier
                                                name:(NSString *)name
                                                icon:(NSImage *)icon
                                           isDefault:(BOOL)isDefault
                                      platformObject:(id)platformObject
{
  LDOpenWithApplication *application = [[LDOpenWithApplication alloc] init];
  application->_identifier = [identifier copy];
  application->_name = [name copy];
  application->_icon = icon;
  application->_default = isDefault;
  application->_platformObject = platformObject;
  return application;
}

- (NSString *)identifier { return _identifier; }
- (NSString *)name { return _name; }
- (NSImage *)icon { return _icon; }
- (BOOL)isDefault { return _default; }
- (id)platformObject { return _platformObject; }

- (NSString *)description
{
  return [NSString stringWithFormat:@"<LDOpenWithApplication %@%@>", _identifier, _default ? @" (default)" : @""];
}

@end

#if defined(__APPLE__)

// STUB: the NSWorkspace backend is still to be written (parity plan M9).
// It should list -[NSWorkspace URLsForApplicationsToOpenURL:] for every
// path, keep the applications common to all of them, put
// -URLForApplicationToOpenURL: first as the default, use the bundle
// identifier as identifier, the display name as name and
// -[NSWorkspace iconForFile:] at 16 points as icon, and open with
// -openURLs:withApplicationAtURL:configuration:completionHandler:.
@implementation LDOpenWith

+ (LDOpenWith *)sharedOpenWith
{
  static LDOpenWith *shared = nil;
  if (!shared) {
    shared = [[LDOpenWith alloc] init];
  }
  return shared;
}

- (NSArray *)applicationsForPaths:(NSArray *)paths
{
  (void)paths;
  return @[];
}

- (BOOL)openPaths:(NSArray *)paths withApplication:(LDOpenWithApplication *)application
{
  (void)paths;
  (void)application;
  return NO;
}

@end

#endif
