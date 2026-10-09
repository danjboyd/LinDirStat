#import "LDDesktop.h"
#import "LDFileOperations.h"

#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

@implementation LDDesktop

static NSData *LDParentOf(NSData *path)
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

+ (NSString *)fileURIForPath:(NSData *)path
{
  return [@"file://" stringByAppendingString:[LDFileOperations percentEncodedPath:path]];
}

+ (NSArray *)openCommandsForPath:(NSData *)path
{
#if defined(__APPLE__)
  return @[@[@"open", path]];
#else
  return @[@[@"xdg-open", path]];
#endif
}

+ (NSArray *)revealCommandsForPath:(NSData *)path
{
#if defined(__APPLE__)
  return @[@[@"open", @"-R", path]];
#else
  // The freedesktop FileManager1 interface opens the folder with the item
  // selected (Nautilus, Dolphin, Nemo, Thunar...); without it, open the
  // containing folder.
  NSString *uri = [self fileURIForPath:path];
  return @[
    @[@"gdbus", @"call", @"--session",
      @"--dest", @"org.freedesktop.FileManager1",
      @"--object-path", @"/org/freedesktop/FileManager1",
      @"--method", @"org.freedesktop.FileManager1.ShowItems",
      [NSString stringWithFormat:@"['%@']", uri], @""],
    @[@"dbus-send", @"--session", @"--print-reply",
      @"--dest=org.freedesktop.FileManager1", @"/org/freedesktop/FileManager1",
      @"org.freedesktop.FileManager1.ShowItems",
      [@"array:string:" stringByAppendingString:uri], @"string:"],
    @[@"xdg-open", LDParentOf(path)],
  ];
#endif
}

+ (NSArray *)terminalCommandsForDirectory:(NSData *)directory
{
#if defined(__APPLE__)
  return @[@[@"open", @"-a", @"Terminal", directory]];
#else
  NSMutableArray *commands = [NSMutableArray array];
  NSString *preferred = [[[NSProcessInfo processInfo] environment] objectForKey:@"TERMINAL"];
  if ([preferred length] > 0) {
    [commands addObject:@[preferred]];
  }
  NSMutableData *workingDirectory = [NSMutableData dataWithBytes:"--working-directory=" length:20];
  [workingDirectory appendData:directory];
  [commands addObjectsFromArray:@[
    @[@"kgx", workingDirectory],
    @[@"gnome-terminal", workingDirectory],
    @[@"ptyxis", @"--new-window", @"--working-directory", directory],
    @[@"konsole", @"--workdir", directory],
    @[@"xfce4-terminal", workingDirectory],
    @[@"x-terminal-emulator"],
    @[@"xterm"],
  ]];
  return commands;
#endif
}

+ (NSString *)pathOfExecutable:(NSString *)name
{
  if ([name hasPrefix:@"/"]) {
    return access([name fileSystemRepresentation], X_OK) == 0 ? name : nil;
  }
  NSString *searchPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
  for (NSString *directory in [searchPath componentsSeparatedByString:@":"]) {
    if ([directory length] == 0) {
      continue;
    }
    NSString *candidate = [directory stringByAppendingPathComponent:name];
    struct stat info;
    if (stat([candidate fileSystemRepresentation], &info) == 0 && S_ISREG(info.st_mode)
        && access([candidate fileSystemRepresentation], X_OK) == 0) {
      return candidate;
    }
  }
  return nil;
}

static NSData *LDArgumentBytes(id argument)
{
  if ([argument isKindOfClass:[NSData class]]) {
    return argument;
  }
  const char *bytes = [(NSString *)argument UTF8String];
  return [NSData dataWithBytes:bytes length:strlen(bytes)];
}

// Spawns command (whose program must be a full path) with stdin and stdout
// on /dev/null. Returns the pid, or -1.
static pid_t LDSpawn(NSString *program, NSArray *command, NSData *directory)
{
  NSMutableArray *storage = [NSMutableArray array];
  NSUInteger count = [command count];
  char **argv = calloc(count + 1, sizeof(char *));
  for (NSUInteger i = 0; i < count; i++) {
    NSMutableData *argument = [LDArgumentBytes([command objectAtIndex:i]) mutableCopy];
    [argument appendBytes:"\0" length:1];
    [storage addObject:argument];
    argv[i] = [argument mutableBytes];
  }

  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
  posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
  NSMutableData *directoryBytes = nil;
  if (directory) {
    directoryBytes = [directory mutableCopy];
    [directoryBytes appendBytes:"\0" length:1];
#if defined(__GLIBC__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 29))
    posix_spawn_file_actions_addchdir_np(&actions, [directoryBytes bytes]);
#endif
  }
  // Children get their own process group so they outlive us cleanly.
  posix_spawnattr_t attributes;
  posix_spawnattr_init(&attributes);
  posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
  posix_spawnattr_setpgroup(&attributes, 0);

  pid_t pid = -1;
  int result = posix_spawn(&pid, [program fileSystemRepresentation], &actions, &attributes, argv, environ);
  posix_spawnattr_destroy(&attributes);
  posix_spawn_file_actions_destroy(&actions);
  free(argv);
  return result == 0 ? pid : -1;
}

+ (void)runFirstSuccessfulCommand:(NSArray *)commands
                      inDirectory:(NSData *)directory
                       completion:(void (^)(BOOL succeeded))completion
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    BOOL succeeded = NO;
    for (NSArray *command in commands) {
      NSString *program = [self pathOfExecutable:[command objectAtIndex:0]];
      pid_t pid = program ? LDSpawn(program, command, directory) : -1;
      if (pid < 0) {
        continue;
      }
      int status = 0;
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
      }
      if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
        succeeded = YES;
        break;
      }
    }
    if (completion) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(succeeded);
      });
    }
  });
}

+ (BOOL)launchFirstAvailableCommand:(NSArray *)commands inDirectory:(NSData *)directory
{
  for (NSArray *command in commands) {
    NSString *program = [self pathOfExecutable:[command objectAtIndex:0]];
    pid_t pid = program ? LDSpawn(program, command, directory) : -1;
    if (pid < 0) {
      continue;
    }
    // Reap it whenever it exits.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
      int status = 0;
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
      }
    });
    return YES;
  }
  return NO;
}

@end
