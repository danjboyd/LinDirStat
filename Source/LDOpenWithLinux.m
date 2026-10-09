#import "LDOpenWithLinux.h"

#if !defined(__APPLE__)

#import "LDDesktop.h"
#import "LDDesktopEntry.h"
#import "LDFileTypeDescriptions.h"
#import "LDMimeApps.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

@interface LDOpenWith ()
{
  LDMimeApps *_mimeApps;
  LDFileTypeDescriptions *_typeDescriptions;
}
@end

static NSData *LDTerminated(NSData *path)
{
  NSMutableData *terminated = [path mutableCopy];
  [terminated appendBytes:"\0" length:1];
  return terminated;
}

static NSData *LDParentDirectory(NSData *path)
{
  const char *bytes = [path bytes];
  NSUInteger length = [path length];
  while (length > 0 && bytes[length - 1] != '/') {
    length--;
  }
  if (length > 1) {
    length--;
  }
  return length == 0 ? [NSData dataWithBytes:"." length:1] : [NSData dataWithBytes:bytes length:length];
}

// Leading bytes with no NUL that are valid UTF-8 (a character cut off at
// the end of the sample is allowed).
static BOOL LDLooksLikeText(const unsigned char *bytes, size_t length)
{
  size_t i = 0;
  while (i < length) {
    unsigned char c = bytes[i];
    if (c == 0) {
      return NO;
    }
    size_t extra = c < 0x80 ? 0 : (c >> 5) == 0x6 ? 1 : (c >> 4) == 0xE ? 2 : (c >> 3) == 0x1E ? 3 : 4;
    if (extra == 4) {
      return NO;
    }
    for (size_t k = 1; k <= extra; k++) {
      if (i + k >= length) {
        return YES;
      }
      if ((bytes[i + k] & 0xC0) != 0x80) {
        return NO;
      }
    }
    i += extra + 1;
  }
  return YES;
}

@implementation LDOpenWith

+ (LDOpenWith *)sharedOpenWith
{
  static LDOpenWith *shared = nil;
  if (!shared) {
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    LDMimeApps *mimeApps = [[LDMimeApps alloc] initWithApplicationDirectories:[LDMimeApps applicationDirectoriesForEnvironment:environment]
                                                            mimeappsListPaths:[LDMimeApps mimeappsListPathsForEnvironment:environment]
                                                                mimeDirectory:@"/usr/share/mime"];
    shared = [[LDOpenWith alloc] initWithMimeApps:mimeApps typeDescriptions:[LDFileTypeDescriptions sharedDescriptions]];
  }
  return shared;
}

- (NSArray *)applicationsForPaths:(NSArray *)paths
{
  if ([paths count] == 0) {
    return @[];
  }
  [_mimeApps reloadIfChanged];
  NSMutableArray *types = [NSMutableArray array];
  for (NSData *path in paths) {
    NSString *type = [self mimeTypeForPath:path];
    if (![types containsObject:type]) {
      [types addObject:type];
    }
  }
  NSMutableArray *entries = [[_mimeApps entriesForType:[types objectAtIndex:0]] mutableCopy];
  LDDesktopEntry *defaultEntry = [_mimeApps defaultEntryForType:[types objectAtIndex:0]];
  for (NSUInteger i = 1; i < [types count]; i++) {
    NSArray *others = [_mimeApps entriesForType:[types objectAtIndex:i]];
    for (LDDesktopEntry *entry in [entries copy]) {
      if ([others indexOfObjectIdenticalTo:entry] == NSNotFound) {
        [entries removeObject:entry];
      }
    }
    // A mixed selection has a default only when every type agrees on it.
    if ([_mimeApps defaultEntryForType:[types objectAtIndex:i]] != defaultEntry) {
      defaultEntry = nil;
    }
  }
  if (defaultEntry && [entries indexOfObjectIdenticalTo:defaultEntry] == NSNotFound) {
    defaultEntry = nil;
  }
  if (defaultEntry) {
    [entries removeObjectIdenticalTo:defaultEntry];
  }
  [entries sortUsingComparator:^NSComparisonResult(LDDesktopEntry *left, LDDesktopEntry *right) {
    NSComparisonResult result = [[left name] caseInsensitiveCompare:[right name]];
    return result != NSOrderedSame ? result : [[left identifier] compare:[right identifier]];
  }];
  if (defaultEntry) {
    [entries insertObject:defaultEntry atIndex:0];
  }
  NSMutableArray *applications = [NSMutableArray array];
  for (LDDesktopEntry *entry in entries) {
    [applications addObject:[LDOpenWithApplication applicationWithIdentifier:[entry identifier]
                                                                        name:[entry name]
                                                                        icon:nil
                                                                   isDefault:entry == defaultEntry
                                                              platformObject:entry]];
  }
  return applications;
}

- (BOOL)openPaths:(NSArray *)paths withApplication:(LDOpenWithApplication *)application
{
  LDDesktopEntry *entry = [application platformObject];
  NSArray *commands = [entry isKindOfClass:[LDDesktopEntry class]] ? [entry commandsForPaths:paths] : nil;
  if ([commands count] == 0) {
    return NO;
  }
  NSString *workingDirectory = [entry stringForKey:@"Path"];
  NSData *directory = [workingDirectory length] > 0
    ? [NSData dataWithBytes:[workingDirectory fileSystemRepresentation] length:strlen([workingDirectory fileSystemRepresentation])]
    : nil;
  BOOL launched = YES;
  for (NSArray *command in commands) {
    NSArray *candidates = @[command];
    if ([entry runsInTerminal]) {
      candidates = [LDDesktop terminalCommandsRunning:command inDirectory:directory ?: LDParentDirectory([paths firstObject])];
    }
    launched = [LDDesktop launchFirstAvailableCommand:candidates inDirectory:directory] && launched;
  }
  return launched;
}

@end

@implementation LDOpenWith (Linux)

- (id)initWithMimeApps:(LDMimeApps *)mimeApps typeDescriptions:(LDFileTypeDescriptions *)typeDescriptions
{
  self = [super init];
  if (self) {
    _mimeApps = mimeApps;
    _typeDescriptions = typeDescriptions;
  }
  return self;
}

- (NSString *)extensionKeyOfPath:(NSData *)path
{
  const char *bytes = [path bytes];
  NSUInteger length = [path length];
  NSUInteger nameStart = length;
  while (nameStart > 0 && bytes[nameStart - 1] != '/') {
    nameStart--;
  }
  NSUInteger dot = length;
  while (dot > nameStart && bytes[dot - 1] != '.') {
    dot--;
  }
  // No dot, or only a leading one (".bashrc").
  if (dot <= nameStart + 1 || dot == length) {
    return nil;
  }
  NSString *extension = [[NSString alloc] initWithBytes:bytes + dot length:length - dot encoding:NSUTF8StringEncoding];
  return [extension lowercaseString];
}

- (NSString *)mimeTypeForPath:(NSData *)path
{
  NSData *terminated = LDTerminated(path);
  struct stat info;
  if (stat([terminated bytes], &info) != 0 && lstat([terminated bytes], &info) != 0) {
    return @"application/octet-stream";
  }
  if (S_ISDIR(info.st_mode)) {
    return @"inode/directory";
  }
  NSString *type = [_typeDescriptions mimeTypeForExtensionKey:[self extensionKeyOfPath:path]];
  if (type) {
    return type;
  }
  if (!S_ISREG(info.st_mode)) {
    return @"application/octet-stream";
  }
  unsigned char sample[512];
  ssize_t length = -1;
  int fd = open([terminated bytes], O_RDONLY | O_CLOEXEC | O_NONBLOCK);
  if (fd >= 0) {
    length = read(fd, sample, sizeof(sample));
    close(fd);
  }
  return length >= 0 && LDLooksLikeText(sample, (size_t)length) ? @"text/plain" : @"application/octet-stream";
}

@end

#endif
