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

// Launch Services decides which applications can open each path. The
// applications offered are those that can open every selected path, keyed
// by application URL (another copy of an app is a different entry, as in
// Finder). The default is the first path's default application when it can
// open them all.
@implementation LDOpenWith

+ (LDOpenWith *)sharedOpenWith
{
  static LDOpenWith *shared = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[LDOpenWith alloc] init];
  });
  return shared;
}

static NSURL *LDFileURL(NSData *path)
{
  NSMutableData *terminated = [path mutableCopy];
  [terminated appendBytes:"\0" length:1];
  return [NSURL fileURLWithFileSystemRepresentation:[terminated bytes] isDirectory:NO relativeToURL:nil];
}

- (NSArray *)applicationsForPaths:(NSArray *)paths
{
  if ([paths count] == 0) {
    return @[];
  }
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSMutableOrderedSet *common = nil;
  NSURL *defaultApplication = nil;
  for (NSData *path in paths) {
    NSURL *url = LDFileURL(path);
    NSArray *candidates = [workspace URLsForApplicationsToOpenURL:url];
    if (!common) {
      common = [NSMutableOrderedSet orderedSetWithArray:candidates];
      defaultApplication = [workspace URLForApplicationToOpenURL:url];
    } else {
      [common intersectSet:[NSSet setWithArray:candidates]];
    }
    if ([common count] == 0) {
      return @[];
    }
  }

  // Names as Finder shows them. Copies of one application (another
  // version, a mounted disk image) are told apart by version, else by
  // where they are.
  NSFileManager *files = [NSFileManager defaultManager];
  NSMutableArray *labels = [NSMutableArray array];
  for (NSURL *applicationURL in common) {
    NSString *name = [files displayNameAtPath:[applicationURL path]];
    if ([name hasSuffix:@".app"]) {
      name = [name stringByDeletingPathExtension];
    }
    [labels addObject:name];
  }
  for (NSUInteger pass = 0; pass < 2; pass++) {
    NSCountedSet *counts = [NSCountedSet setWithArray:labels];
    for (NSUInteger i = 0; i < [labels count]; i++) {
      if ([counts countForObject:[labels objectAtIndex:i]] < 2) {
        continue;
      }
      NSURL *applicationURL = [common objectAtIndex:i];
      NSString *suffix = nil;
      if (pass == 0) {
        suffix = [[NSBundle bundleWithURL:applicationURL] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        suffix = [suffix length] > 0 ? [NSString stringWithFormat:@" (%@)", suffix] : nil;
      } else {
        suffix = [@" — " stringByAppendingString:
                  [[[applicationURL path] stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath]];
      }
      if (suffix) {
        [labels replaceObjectAtIndex:i withObject:[[labels objectAtIndex:i] stringByAppendingString:suffix]];
      }
    }
  }

  NSMutableArray *applications = [NSMutableArray array];
  LDOpenWithApplication *defaultEntry = nil;
  NSUInteger index = 0;
  for (NSURL *applicationURL in common) {
    NSBundle *bundle = [NSBundle bundleWithURL:applicationURL];
    NSString *identifier = [bundle bundleIdentifier] ?: [applicationURL path];
    NSImage *icon = [[workspace iconForFile:[applicationURL path]] copy];
    [icon setSize:NSMakeSize(16.0, 16.0)];
    BOOL isDefault = defaultApplication && [applicationURL isEqual:defaultApplication];
    LDOpenWithApplication *application = [LDOpenWithApplication applicationWithIdentifier:identifier
                                                                                     name:[labels objectAtIndex:index++]
                                                                                     icon:icon
                                                                                isDefault:isDefault
                                                                           platformObject:applicationURL];
    if (isDefault && !defaultEntry) {
      defaultEntry = application;
    } else {
      [applications addObject:application];
    }
  }
  [applications sortUsingComparator:^NSComparisonResult(LDOpenWithApplication *left, LDOpenWithApplication *right) {
    NSComparisonResult order = [[left name] localizedStandardCompare:[right name]];
    return order != NSOrderedSame ? order : [[[left platformObject] path] compare:[[right platformObject] path]];
  }];
  if (defaultEntry) {
    [applications insertObject:defaultEntry atIndex:0];
  }
  return applications;
}

- (BOOL)openPaths:(NSArray *)paths withApplication:(LDOpenWithApplication *)application
{
  NSURL *applicationURL = [application platformObject];
  if ([paths count] == 0 || ![applicationURL isKindOfClass:[NSURL class]]
      || ![applicationURL checkResourceIsReachableAndReturnError:NULL]) {
    return NO;
  }
  NSMutableArray *urls = [NSMutableArray arrayWithCapacity:[paths count]];
  for (NSData *path in paths) {
    [urls addObject:LDFileURL(path)];
  }
  NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
  [configuration setActivates:YES];
  [[NSWorkspace sharedWorkspace] openURLs:urls
                     withApplicationAtURL:applicationURL
                            configuration:configuration
                        completionHandler:^(NSRunningApplication *running, NSError *error) {
    (void)running;
    if (error) {
      NSLog(@"LinDirStat: could not open with %@: %@", [application name], [error localizedDescription]);
    }
  }];
  return YES;
}

@end

#endif
