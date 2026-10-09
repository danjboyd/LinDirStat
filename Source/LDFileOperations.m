#import "LDFileOperations.h"
#import "LDDesktop.h"

#include <dirent.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#if !defined(__APPLE__)
#include <sys/syscall.h>
#endif
#include <time.h>
#include <unistd.h>

#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif

static NSError *LDPOSIXError(int code, NSString *step)
{
  NSString *description = [NSString stringWithFormat:@"%@: %s", step, strerror(code)];
  return [NSError errorWithDomain:NSPOSIXErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL LDFail(NSError **error, int code, NSString *step)
{
  if (error) {
    *error = LDPOSIXError(code, step);
  }
  return NO;
}

// NUL-terminated copy of path bytes.
static NSMutableData *LDTerminated(NSData *path)
{
  NSMutableData *copy = [path mutableCopy];
  [copy appendBytes:"\0" length:1];
  return copy;
}

static NSData *LDDirectoryPart(NSData *path)
{
  const char *bytes = [path bytes];
  NSUInteger length = [path length];
  while (length > 1 && bytes[length - 1] == '/') {
    length--;
  }
  while (length > 0 && bytes[length - 1] != '/') {
    length--;
  }
  while (length > 1 && bytes[length - 1] == '/') {
    length--;
  }
  return length == 0 ? [NSData dataWithBytes:"." length:1] : [NSData dataWithBytes:bytes length:length];
}

static NSData *LDNamePart(NSData *path)
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

static NSData *LDJoin(NSData *directory, const char *name, size_t length)
{
  NSMutableData *joined = [directory mutableCopy];
  if ([joined length] == 0 || ((const char *)[joined bytes])[[joined length] - 1] != '/') {
    [joined appendBytes:"/" length:1];
  }
  [joined appendBytes:name length:length];
  return joined;
}

static NSData *LDJoinString(NSData *directory, const char *name)
{
  return LDJoin(directory, name, strlen(name));
}

@implementation LDFileOperations

+ (NSString *)percentEncodedPath:(NSData *)path
{
  static const char *hex = "0123456789ABCDEF";
  const unsigned char *bytes = [path bytes];
  NSMutableString *encoded = [NSMutableString stringWithCapacity:[path length]];
  for (NSUInteger i = 0; i < [path length]; i++) {
    unsigned char c = bytes[i];
    BOOL unreserved = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
      || c == '-' || c == '.' || c == '_' || c == '~' || c == '/';
    if (unreserved) {
      [encoded appendFormat:@"%c", c];
    } else {
      [encoded appendFormat:@"%%%c%c", hex[c >> 4], hex[c & 0xF]];
    }
  }
  return encoded;
}

#if defined(__APPLE__)

+ (NSData *)trashDirectoryForPath:(NSData *)path error:(NSError **)error
{
  (void)path;
  LDFail(error, ENOTSUP, @"Finding the trash");
  return nil;
}

+ (BOOL)moveToTrash:(NSData *)path error:(NSError **)error
{
  NSMutableData *terminated = LDTerminated(path);
  struct stat info;
  if (lstat([terminated bytes], &info) != 0) {
    return LDFail(error, errno, @"Reading the item");
  }
  NSURL *url = [NSURL fileURLWithFileSystemRepresentation:[terminated bytes] isDirectory:NO relativeToURL:nil];
  return [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:NULL error:error];
}

#else

// Creates directory (mode 0700) unless it exists; it must then be a real
// directory owned by us, not a symlink.
static BOOL LDEnsurePrivateDirectory(NSData *directory, NSError **error)
{
  NSMutableData *terminated = LDTerminated(directory);
  if (mkdir([terminated bytes], 0700) != 0 && errno != EEXIST) {
    return LDFail(error, errno, @"Creating the trash");
  }
  struct stat info;
  if (lstat([terminated bytes], &info) != 0) {
    return LDFail(error, errno, @"Checking the trash");
  }
  if (!S_ISDIR(info.st_mode) || info.st_uid != getuid()) {
    return LDFail(error, EPERM, @"Checking the trash");
  }
  return YES;
}

static BOOL LDEnsureTrash(NSData *trash, NSError **error)
{
  return LDEnsurePrivateDirectory(trash, error)
    && LDEnsurePrivateDirectory(LDJoinString(trash, "files"), error)
    && LDEnsurePrivateDirectory(LDJoinString(trash, "info"), error);
}

static NSData *LDHomeTrash(void)
{
  const char *dataHome = getenv("XDG_DATA_HOME");
  NSData *base = nil;
  if (dataHome && dataHome[0] == '/') {
    base = [NSData dataWithBytes:dataHome length:strlen(dataHome)];
  } else {
    const char *home = getenv("HOME");
    if (!home || home[0] != '/') {
      return nil;
    }
    base = LDJoinString([NSData dataWithBytes:home length:strlen(home)], ".local/share");
  }
  return LDJoinString(base, "Trash");
}

static NSData *LDCanonicalPath(NSData *path, NSError **error)
{
  // The parent is resolved, not the item, which may itself be a symlink.
  NSMutableData *parent = LDTerminated(LDDirectoryPart(path));
  char resolved[PATH_MAX];
  if (realpath([parent bytes], resolved) == NULL) {
    LDFail(error, errno, @"Resolving the folder");
    return nil;
  }
  NSData *name = LDNamePart(path);
  return LDJoin([NSData dataWithBytes:resolved length:strlen(resolved)], [name bytes], [name length]);
}

// The mount point containing canonical path's parent.
static NSData *LDTopDirectory(NSData *canonicalPath, dev_t device)
{
  NSData *directory = LDDirectoryPart(canonicalPath);
  while ([directory length] > 1) {
    NSData *up = LDDirectoryPart(directory);
    struct stat info;
    if (stat([LDTerminated(up) bytes], &info) != 0 || info.st_dev != device) {
      break;
    }
    directory = up;
  }
  return directory;
}

static BOOL LDTrashIsOnDevice(NSData *trash, dev_t device)
{
  struct stat info;
  return stat([LDTerminated(trash) bytes], &info) == 0 && info.st_dev == device;
}

// Finds the trash for an item; *topDirectory is set to the mount point for a
// per-volume trash and to nil for the home trash.
static NSData *LDTrashForItem(NSData *canonicalPath, dev_t device, NSData **topDirectory, NSError **error)
{
  *topDirectory = nil;
  NSData *home = LDHomeTrash();
  if (home) {
    NSData *homeBase = LDDirectoryPart(home);
    struct stat info;
    if (stat([LDTerminated(homeBase) bytes], &info) == 0 && info.st_dev == device) {
      return LDEnsureTrash(home, error) ? home : nil;
    }
  }

  NSData *top = LDTopDirectory(canonicalPath, device);
  NSString *uid = [NSString stringWithFormat:@"%u", (unsigned)getuid()];
  NSData *shared = LDJoinString(top, ".Trash");
  struct stat sharedInfo;
  if (lstat([LDTerminated(shared) bytes], &sharedInfo) == 0
      && S_ISDIR(sharedInfo.st_mode) && (sharedInfo.st_mode & S_ISVTX)) {
    NSData *mine = LDJoinString(shared, [uid UTF8String]);
    if (LDEnsureTrash(mine, NULL) && LDTrashIsOnDevice(mine, device)) {
      *topDirectory = top;
      return mine;
    }
  }
  NSData *personal = LDJoinString(top, [[@".Trash-" stringByAppendingString:uid] UTF8String]);
  if (LDEnsureTrash(personal, error) && LDTrashIsOnDevice(personal, device)) {
    *topDirectory = top;
    return personal;
  }
  if (error && !*error) {
    *error = LDPOSIXError(EXDEV, @"Finding a trash on the item's filesystem");
  }
  return nil;
}

+ (NSData *)trashDirectoryForPath:(NSData *)path error:(NSError **)error
{
  struct stat info;
  if (lstat([LDTerminated(path) bytes], &info) != 0) {
    LDFail(error, errno, @"Reading the item");
    return nil;
  }
  NSData *canonical = LDCanonicalPath(path, error);
  NSData *top = nil;
  return canonical ? LDTrashForItem(canonical, info.st_dev, &top, error) : nil;
}

static int LDRenameNoReplace(const char *from, const char *to)
{
#ifdef SYS_renameat2
  int result = (int)syscall(SYS_renameat2, AT_FDCWD, from, AT_FDCWD, to, RENAME_NOREPLACE);
  if (result == 0 || (errno != ENOSYS && errno != EINVAL)) {
    return result;
  }
#endif
  struct stat existing;
  if (lstat(to, &existing) == 0) {
    errno = EEXIST;
    return -1;
  }
  return rename(from, to);
}

+ (BOOL)moveToTrash:(NSData *)path error:(NSError **)error
{
  struct stat info;
  NSMutableData *source = LDTerminated(path);
  if (lstat([source bytes], &info) != 0) {
    return LDFail(error, errno, @"Reading the item");
  }
  NSData *canonical = LDCanonicalPath(path, error);
  if (!canonical) {
    return NO;
  }
  NSData *top = nil;
  NSData *trash = LDTrashForItem(canonical, info.st_dev, &top, error);
  if (!trash) {
    return NO;
  }

  // Path= is absolute for the home trash and relative to the mount point
  // for a per-volume trash.
  NSData *recorded = canonical;
  if (top) {
    NSUInteger skip = [top length] == 1 ? 1 : [top length] + 1;
    recorded = [canonical subdataWithRange:NSMakeRange(skip, [canonical length] - skip)];
  }
  char date[32];
  time_t now = time(NULL);
  struct tm local;
  localtime_r(&now, &local);
  strftime(date, sizeof(date), "%Y-%m-%dT%H:%M:%S", &local);
  NSString *infoText = [NSString stringWithFormat:@"[Trash Info]\nPath=%@\nDeletionDate=%s\n",
                        [self percentEncodedPath:recorded], date];
  NSData *infoBytes = [infoText dataUsingEncoding:NSUTF8StringEncoding];

  // The .trashinfo file is created exclusively first; its name reserves the
  // matching name under files/.
  NSData *name = LDNamePart(path);
  NSData *filesDirectory = LDJoinString(trash, "files");
  NSData *infoDirectory = LDJoinString(trash, "info");
  for (NSUInteger attempt = 1; attempt < 10000; attempt++) {
    char suffix[16] = "";
    if (attempt > 1) {
      snprintf(suffix, sizeof(suffix), ".%lu", (unsigned long)attempt);
    }
    size_t limit = NAME_MAX - strlen(".trashinfo") - strlen(suffix);
    NSMutableData *candidate = [NSMutableData dataWithBytes:[name bytes] length:MIN([name length], limit)];
    [candidate appendBytes:suffix length:strlen(suffix)];
    NSMutableData *infoName = [candidate mutableCopy];
    [infoName appendBytes:".trashinfo" length:strlen(".trashinfo")];

    NSMutableData *infoPath = LDTerminated(LDJoin(infoDirectory, [infoName bytes], [infoName length]));
    int fd = open([infoPath bytes], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd < 0) {
      if (errno == EEXIST) {
        continue;
      }
      return LDFail(error, errno, @"Writing the trash information");
    }
    ssize_t written = write(fd, [infoBytes bytes], [infoBytes length]);
    int writeError = errno;
    close(fd);
    if (written != (ssize_t)[infoBytes length]) {
      unlink([infoPath bytes]);
      return LDFail(error, written < 0 ? writeError : EIO, @"Writing the trash information");
    }

    NSMutableData *target = LDTerminated(LDJoin(filesDirectory, [candidate bytes], [candidate length]));
    if (LDRenameNoReplace([source bytes], [target bytes]) == 0) {
      return YES;
    }
    int renameError = errno;
    unlink([infoPath bytes]);
    if (renameError != EEXIST) {
      return LDFail(error, renameError, @"Moving the item to the trash");
    }
  }
  return LDFail(error, EEXIST, @"Naming the item in the trash");
}

#endif

// Removes name (relative to directoryFD) and, for a directory, everything in
// it. Keeps going past failures and returns the first errno, or 0.
static int LDRemoveTree(int directoryFD, const char *name, dev_t device)
{
  struct stat info;
  if (fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
    return errno;
  }
  if (!S_ISDIR(info.st_mode)) {
    return unlinkat(directoryFD, name, 0) == 0 ? 0 : errno;
  }
  if (info.st_dev != device) {
    return EXDEV;
  }
  int fd = openat(directoryFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) {
    return errno;
  }
  struct stat opened;
  if (fstat(fd, &opened) != 0 || opened.st_dev != info.st_dev || opened.st_ino != info.st_ino) {
    close(fd);
    return EAGAIN;
  }
  DIR *directory = fdopendir(fd);
  if (!directory) {
    int openError = errno;
    close(fd);
    return openError;
  }
  int firstError = 0;
  struct dirent *entry = NULL;
  while ((entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    int result = LDRemoveTree(dirfd(directory), entry->d_name, device);
    if (result != 0 && firstError == 0) {
      firstError = result;
    }
  }
  closedir(directory);
  if (firstError != 0) {
    return firstError;
  }
  return unlinkat(directoryFD, name, AT_REMOVEDIR) == 0 ? 0 : errno;
}

+ (BOOL)deletePermanently:(NSData *)path error:(NSError **)error
{
  struct stat info;
  if (lstat([LDTerminated(path) bytes], &info) != 0) {
    return LDFail(error, errno, @"Reading the item");
  }
  NSMutableData *parent = LDTerminated(LDDirectoryPart(path));
  NSMutableData *name = LDTerminated(LDNamePart(path));
  int parentFD = open([parent bytes], O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (parentFD < 0) {
    return LDFail(error, errno, @"Opening the folder");
  }
  int result = LDRemoveTree(parentFD, [name bytes], info.st_dev);
  close(parentFD);
  if (result != 0) {
    return LDFail(error, result, result == EXDEV ? @"Deleting stopped at a mounted filesystem" : @"Deleting");
  }
  return YES;
}

+ (BOOL)moveItem:(NSData *)path toDirectory:(NSData *)directory error:(NSError **)error
{
  NSMutableData *source = LDTerminated(path);
  NSData *name = LDNamePart(path);
  NSMutableData *target = LDTerminated(LDJoin(directory, [name bytes], [name length]));
  struct stat info;
  if (lstat([source bytes], &info) != 0) {
    return LDFail(error, errno, @"Reading the item");
  }
  if (lstat([target bytes], &info) == 0) {
    return LDFail(error, EEXIST, @"Moving");
  }
#if defined(__APPLE__)
  if (renamex_np([source bytes], [target bytes], RENAME_EXCL) == 0) {
    return YES;
  }
#else
  if (LDRenameNoReplace([source bytes], [target bytes]) == 0) {
    return YES;
  }
#endif
  if (errno != EXDEV) {
    return LDFail(error, errno, @"Moving");
  }
  // Another filesystem: let mv copy and remove, without overwriting.
  __block BOOL moved = NO;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  NSArray *command = @[@"mv", @"-n", @"--", path, directory];
  [LDDesktop runFirstSuccessfulCommand:@[command] inDirectory:nil queue:nil completion:^(BOOL succeeded) {
    moved = succeeded;
    dispatch_semaphore_signal(done);
  }];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  if (!moved || lstat([target bytes], &info) != 0) {
    return LDFail(error, EIO, @"Moving to another filesystem");
  }
  return YES;
}

+ (NSArray *)existingTrashDirectories
{
#if defined(__APPLE__)
  return @[];
#else
  NSMutableArray *trashes = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  // Emptying deletes for good, so every trash must be what the spec says:
  // a real directory owned by us (never a symlink placed on a removable
  // volume), with real files/ and info/ folders.
  BOOL (^ownedDirectory)(NSData *) = ^BOOL(NSData *directory) {
    struct stat info;
    return lstat([LDTerminated(directory) bytes], &info) == 0
      && S_ISDIR(info.st_mode) && info.st_uid == getuid();
  };
  void (^consider)(NSData *) = ^(NSData *trash) {
    if ([seen containsObject:trash] || !ownedDirectory(trash)
        || !ownedDirectory(LDJoinString(trash, "files")) || !ownedDirectory(LDJoinString(trash, "info"))) {
      return;
    }
    [seen addObject:trash];
    [trashes addObject:trash];
  };
  NSData *home = LDHomeTrash();
  if (home) {
    consider(home);
  }
  NSString *uid = [NSString stringWithFormat:@"%u", (unsigned)getuid()];
  NSString *mounts = [NSString stringWithContentsOfFile:@"/proc/self/mounts" encoding:NSUTF8StringEncoding error:NULL];
  for (NSString *line in [mounts componentsSeparatedByString:@"\n"]) {
    NSArray *fields = [line componentsSeparatedByString:@" "];
    if ([fields count] < 2) {
      continue;
    }
    // /proc/self/mounts escapes spaces and other bytes as octal \ooo.
    NSString *escaped = [fields objectAtIndex:1];
    NSMutableData *top = [NSMutableData data];
    const char *raw = [escaped UTF8String];
    for (size_t i = 0; raw[i]; i++) {
      if (raw[i] == '\\' && raw[i + 1] && raw[i + 2] && raw[i + 3]) {
        char octal[4] = {raw[i + 1], raw[i + 2], raw[i + 3], 0};
        char byte = (char)strtol(octal, NULL, 8);
        [top appendBytes:&byte length:1];
        i += 3;
      } else {
        [top appendBytes:raw + i length:1];
      }
    }
    // $topdir/.Trash must be a sticky, non-symlinked directory.
    NSData *shared = LDJoinString(top, ".Trash");
    struct stat sharedInfo;
    if (lstat([LDTerminated(shared) bytes], &sharedInfo) == 0
        && S_ISDIR(sharedInfo.st_mode) && (sharedInfo.st_mode & S_ISVTX)) {
      consider(LDJoinString(shared, [uid UTF8String]));
    }
    consider(LDJoinString(top, [[@".Trash-" stringByAppendingString:uid] UTF8String]));
  }
  return trashes;
#endif
}

+ (NSData *)systemTrashPath
{
#if defined(__APPLE__)
  const char *trash = [[NSHomeDirectory() stringByAppendingPathComponent:@".Trash"] fileSystemRepresentation];
  return [NSData dataWithBytes:trash length:strlen(trash)];
#else
  return nil;
#endif
}

+ (BOOL)emptySystemTrash:(NSError **)error
{
#if defined(__APPLE__)
  __block BOOL emptied = NO;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  NSArray *command = @[@"osascript", @"-e", @"tell application \"Finder\" to empty trash"];
  [LDDesktop runFirstSuccessfulCommand:@[command] inDirectory:nil queue:nil completion:^(BOOL succeeded) {
    emptied = succeeded;
    dispatch_semaphore_signal(done);
  }];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  if (!emptied && error) {
    NSString *reason = @"Finder did not empty the Trash. If LinDirStat is not allowed to control Finder, "
      @"turn it on in System Settings › Privacy & Security › Automation.";
    *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM
                             userInfo:@{NSLocalizedDescriptionKey: reason}];
  }
  return emptied;
#else
  return LDFail(error, ENOTSUP, @"Emptying the system trash");
#endif
}

+ (NSArray *)trashContentDirectories
{
  NSData *system = [self systemTrashPath];
  if (system) {
    return @[system];
  }
  NSMutableArray *folders = [NSMutableArray array];
  for (NSData *trash in [self existingTrashDirectories]) {
    [folders addObject:LDJoinString(trash, "files")];
  }
  return folders;
}

// Adds up the physical size below directoryFD, depth first, until *budget
// runs out.
static void LDMeasureTree(int directoryFD, unsigned long long *bytes, NSUInteger *budget)
{
  DIR *directory = fdopendir(directoryFD);
  if (!directory) {
    close(directoryFD);
    return;
  }
  struct dirent *entry = NULL;
  while (*budget > 0 && (entry = readdir(directory)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    struct stat info;
    if (fstatat(dirfd(directory), entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
      continue;
    }
    *budget -= 1;
    *bytes += (unsigned long long)info.st_blocks * 512ULL;
    if (S_ISDIR(info.st_mode)) {
      int child = openat(dirfd(directory), entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
      if (child >= 0) {
        LDMeasureTree(child, bytes, budget);
      }
    }
  }
  closedir(directory);
}

+ (void)measureTrashContents:(NSArray *)directories
                  entryLimit:(NSUInteger)entryLimit
                       items:(NSUInteger *)items
                       bytes:(unsigned long long *)bytes
                    complete:(BOOL *)complete
{
  NSUInteger count = 0;
  unsigned long long total = 0;
  NSUInteger budget = entryLimit;
  BOOL unreadable = NO;
  for (NSData *folder in directories) {
    DIR *directory = opendir([LDTerminated(folder) bytes]);
    if (!directory) {
      // No trash yet is an empty trash; one we may not read (macOS without
      // Full Disk Access) is unknown.
      unreadable = unreadable || errno == EPERM || errno == EACCES;
      continue;
    }
    struct dirent *entry = NULL;
    while ((entry = readdir(directory)) != NULL) {
      if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0
          || (strcmp(entry->d_name, ".DS_Store") == 0 && [self systemTrashPath])) {
        continue;
      }
      count++;
      struct stat info;
      if (budget == 0 || fstatat(dirfd(directory), entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
        continue;
      }
      budget--;
      total += (unsigned long long)info.st_blocks * 512ULL;
      if (S_ISDIR(info.st_mode)) {
        int child = openat(dirfd(directory), entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (child >= 0) {
          LDMeasureTree(child, &total, &budget);
        }
      }
    }
    closedir(directory);
  }
  if (items) {
    *items = unreadable ? NSNotFound : count;
  }
  if (bytes) {
    *bytes = total;
  }
  if (complete) {
    *complete = budget > 0 && !unreadable;
  }
}

+ (BOOL)emptyTrashDirectories:(NSArray *)trashDirectories error:(NSError **)error
{
  BOOL emptied = YES;
  for (NSData *trash in trashDirectories) {
    for (NSString *part in @[@"files", @"info", @"expunged"]) {
      NSData *folder = LDJoinString(trash, [part UTF8String]);
      DIR *directory = opendir([LDTerminated(folder) bytes]);
      if (!directory) {
        continue;
      }
      NSMutableArray *entries = [NSMutableArray array];
      struct dirent *entry = NULL;
      while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
          [entries addObject:LDJoinString(folder, entry->d_name)];
        }
      }
      closedir(directory);
      for (NSData *item in entries) {
        NSError *itemError = nil;
        if (![self deletePermanently:item error:&itemError]) {
          if (emptied && error) {
            *error = itemError;
          }
          emptied = NO;
        }
      }
    }
    unlink([LDTerminated(LDJoinString(trash, "directorysizes")) bytes]);
  }
  return emptied;
}

@end
