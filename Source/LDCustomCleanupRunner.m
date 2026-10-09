#import "LDCustomCleanupRunner.h"
#import "LDDesktop.h"
#import "LDPreferences.h"

#include <dirent.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSData *LDLastComponent(NSData *path)
{
  const char *bytes = [path bytes];
  NSUInteger end = [path length];
  while (end > 1 && bytes[end - 1] == '/') {
    end--;
  }
  NSUInteger start = end;
  while (start > 0 && bytes[start - 1] != '/') {
    start--;
  }
  return [NSData dataWithBytes:bytes + start length:end - start];
}

static NSData *LDParentPath(NSData *path)
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

@implementation LDCustomCleanupRunner

+ (NSData *)commandForTemplate:(NSString *)commandTemplate
                          path:(NSData *)path
                 subfolderPath:(NSData *)subfolderPath
{
  NSData *subfolder = subfolderPath ?: path;
  const char *text = [commandTemplate UTF8String];
  size_t length = strlen(text);
  NSMutableData *command = [NSMutableData dataWithCapacity:length + [path length]];
  for (size_t i = 0; i < length; i++) {
    if (text[i] == '%') {
      if (strncmp(text + i + 1, "sp", 2) == 0) {
        [command appendData:subfolder];
        i += 2;
        continue;
      }
      if (strncmp(text + i + 1, "sn", 2) == 0) {
        [command appendData:LDLastComponent(subfolder)];
        i += 2;
        continue;
      }
      if (text[i + 1] == 'p') {
        [command appendData:path];
        i += 1;
        continue;
      }
      if (text[i + 1] == 'n') {
        [command appendData:LDLastComponent(path)];
        i += 1;
        continue;
      }
    }
    [command appendBytes:text + i length:1];
  }
  return command;
}

static void LDCollectPostOrder(int parentFD, const char *name, NSData *path, dev_t device, NSMutableArray *order)
{
  int fd = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) {
    return;
  }
  struct stat info;
  if (fstat(fd, &info) != 0 || info.st_dev != device) {
    close(fd);
    return;
  }
  DIR *directory = fdopendir(fd);
  if (!directory) {
    close(fd);
    return;
  }
  NSMutableArray *subfolders = [NSMutableArray array];
  struct dirent *entry = NULL;
  while ((entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    struct stat child;
    if (fstatat(dirfd(directory), entry->d_name, &child, AT_SYMLINK_NOFOLLOW) == 0 && S_ISDIR(child.st_mode)) {
      [subfolders addObject:[NSData dataWithBytes:entry->d_name length:strlen(entry->d_name) + 1]];
    }
  }
  [subfolders sortUsingComparator:^NSComparisonResult(NSData *a, NSData *b) {
    int order = strcmp([a bytes], [b bytes]);
    return order < 0 ? NSOrderedAscending : (order > 0 ? NSOrderedDescending : NSOrderedSame);
  }];
  for (NSData *subfolder in subfolders) {
    NSMutableData *childPath = [path mutableCopy];
    if ([childPath length] == 0 || ((const char *)[childPath bytes])[[childPath length] - 1] != '/') {
      [childPath appendBytes:"/" length:1];
    }
    [childPath appendBytes:[subfolder bytes] length:[subfolder length] - 1];
    LDCollectPostOrder(dirfd(directory), [subfolder bytes], childPath, device, order);
  }
  closedir(directory);
  [order addObject:path];
}

+ (NSArray *)recursionOrderForFolder:(NSData *)folder
{
  NSMutableData *terminated = [folder mutableCopy];
  [terminated appendBytes:"\0" length:1];
  struct stat info;
  NSMutableArray *order = [NSMutableArray array];
  if (stat([terminated bytes], &info) != 0) {
    return order;
  }
  LDCollectPostOrder(AT_FDCWD, [terminated bytes], folder, info.st_dev, order);
  return order;
}

+ (NSData *)workingDirectoryForPath:(NSData *)path isDirectory:(BOOL)isDirectory
{
  return isDirectory ? path : LDParentPath(path);
}

// Runs one command, waiting for it when asked. Returns NO if it could not
// start or (when waiting) exited unsuccessfully.
+ (BOOL)runCommand:(NSData *)command
       inDirectory:(NSData *)directory
          terminal:(BOOL)terminal
              wait:(BOOL)wait
{
  NSArray *commands = terminal
    ? [LDDesktop terminalCommandsRunning:command inDirectory:directory]
    : @[@[@"/bin/sh", @"-c", command]];
  if (!wait) {
    return [LDDesktop launchFirstAvailableCommand:commands inDirectory:directory];
  }
  __block BOOL succeeded = NO;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  // A terminal that is missing is skipped; a command that fails must not
  // fall through to the next terminal.
  NSArray *installed = nil;
  for (NSArray *candidate in commands) {
    if ([LDDesktop pathOfExecutable:[candidate objectAtIndex:0]]) {
      installed = @[candidate];
      break;
    }
  }
  if (!installed) {
    return NO;
  }
  [LDDesktop runFirstSuccessfulCommand:installed inDirectory:directory queue:nil completion:^(BOOL ok) {
    succeeded = ok;
    dispatch_semaphore_signal(done);
  }];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  return succeeded;
}

+ (void)runCleanup:(LDCustomCleanup *)cleanup
           onPaths:(NSArray *)paths
       directories:(NSArray *)isDirectoryFlags
        completion:(void (^)(NSArray *ranPaths, NSArray *failures))completion
{
  LDCustomCleanup *settings = [cleanup copy];
  [settings normalize];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSMutableArray *ran = [NSMutableArray array];
    NSMutableArray *failures = [NSMutableArray array];
    NSString *commandTemplate = [settings commandLine];
    for (NSUInteger i = 0; i < [paths count]; i++) {
      NSData *path = [paths objectAtIndex:i];
      BOOL isDirectory = [[isDirectoryFlags objectAtIndex:i] boolValue];
      NSArray *folders = (isDirectory && [settings recurseIntoSubdirectories])
        ? [self recursionOrderForFolder:path]
        : @[[self workingDirectoryForPath:path isDirectory:isDirectory]];
      BOOL succeeded = YES;
      for (NSData *folder in folders) {
        NSData *subfolder = [settings recurseIntoSubdirectories] ? folder : nil;
        NSData *command = [self commandForTemplate:commandTemplate path:path subfolderPath:subfolder];
        if (![self runCommand:command
                  inDirectory:folder
                     terminal:[settings showInTerminal]
                         wait:[settings waitForCompletion]]) {
          succeeded = NO;
        }
      }
      [ran addObject:path];
      if (!succeeded) {
        [failures addObject:path];
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(ran, failures);
    });
  });
}

@end
