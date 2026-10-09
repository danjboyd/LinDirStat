#import "LDFileWatcherLinux.h"
#import "LDFileWatcher+Backend.h"

#if !defined(__APPLE__)

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

static const uint32_t LDInotifyMask = IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVED_FROM | IN_MOVED_TO
  | IN_DELETE_SELF | IN_ONLYDIR | IN_DONT_FOLLOW | IN_EXCL_UNLINK;

static NSData *LDJoinPath(NSData *directory, const char *name, size_t nameLength)
{
  NSMutableData *path = [directory mutableCopy];
  const char *bytes = [directory bytes];
  if ([directory length] == 0 || bytes[[directory length] - 1] != '/') {
    [path appendBytes:"/" length:1];
  }
  [path appendBytes:name length:nameLength];
  return path;
}

static BOOL LDPathIsAtOrBelow(NSData *path, NSData *directory)
{
  NSUInteger length = [directory length];
  if ([path length] < length || memcmp([path bytes], [directory bytes], length) != 0) {
    return NO;
  }
  return [path length] == length || ((const char *)[path bytes])[length] == '/'
    || (length > 0 && ((const char *)[directory bytes])[length - 1] == '/');
}

static NSString *LDDisplayPath(NSData *path)
{
  return [[LDFileWatcherEvent eventWithPathData:path action:LDFileWatcherActionCreated time:0 logicalSize:0 isDirectory:NO] path];
}

static unsigned long long LDLogicalSizeOfPath(NSData *path)
{
  NSMutableData *terminated = [path mutableCopy];
  [terminated appendBytes:"\0" length:1];
  struct stat info;
  if (lstat([terminated bytes], &info) != 0 || S_ISDIR(info.st_mode)) {
    return 0;
  }
  return (unsigned long long)info.st_size;
}

@implementation LDInotifyTranslator

- (id)initWithRootPaths:(NSArray *)roots
{
  self = [super init];
  if (self) {
    _roots = [roots copy];
    _paths = [[NSMutableDictionary alloc] init];
    _pendingMovedFrom = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)setPath:(NSData *)path forWatch:(int)watch
{
  [_paths setObject:[path copy] forKey:[NSNumber numberWithInt:watch]];
}

- (NSData *)pathForWatch:(int)watch
{
  return [_paths objectForKey:[NSNumber numberWithInt:watch]];
}

- (void)forgetWatch:(int)watch
{
  [_paths removeObjectForKey:[NSNumber numberWithInt:watch]];
}

- (NSUInteger)watchCount
{
  return [_paths count];
}

- (NSArray *)watchesAtOrBelowPath:(NSData *)path
{
  NSMutableArray *watches = [NSMutableArray array];
  for (NSNumber *watch in _paths) {
    if (LDPathIsAtOrBelow([_paths objectForKey:watch], path)) {
      [watches addObject:watch];
    }
  }
  return watches;
}

// A folder renamed inside the trees keeps its watches under the new name.
- (void)renameWatchedPath:(NSData *)oldPath to:(NSData *)newPath
{
  for (NSNumber *watch in [self watchesAtOrBelowPath:oldPath]) {
    NSData *path = [_paths objectForKey:watch];
    NSMutableData *renamed = [newPath mutableCopy];
    [renamed appendData:[path subdataWithRange:NSMakeRange([oldPath length], [path length] - [oldPath length])]];
    [_paths setObject:renamed forKey:watch];
  }
}

- (BOOL)isRoot:(NSData *)path
{
  for (NSData *root in _roots) {
    if ([root isEqualToData:path]) {
      return YES;
    }
  }
  return NO;
}

- (LDFileWatcherEvent *)eventForPath:(NSData *)path action:(LDFileWatcherAction)action directory:(BOOL)directory time:(NSTimeInterval)time
{
  BOOL gone = action == LDFileWatcherActionDeleted || action == LDFileWatcherActionRenamedOld;
  return [LDFileWatcherEvent eventWithPathData:path
                                        action:action
                                          time:time
                                   logicalSize:gone ? 0 : LDLogicalSizeOfPath(path)
                                   isDirectory:directory];
}

- (NSArray *)eventsForBuffer:(const void *)buffer length:(size_t)length time:(NSTimeInterval)time
{
  _directoriesCreated = [NSMutableArray array];
  _directoriesMovedIn = [NSMutableArray array];
  _watchesToRemove = [NSMutableArray array];
  _messages = [NSMutableArray array];
  NSMutableArray *events = [NSMutableArray array];
  // Moved-from halves of renames, by cookie: the event and its path. They
  // stay held across reads until their moved-to arrives or they are flushed.
  NSMutableDictionary *movedFrom = _pendingMovedFrom;

  const char *bytes = buffer;
  size_t offset = 0;
  while (offset + sizeof(struct inotify_event) <= length) {
    struct inotify_event header;
    memcpy(&header, bytes + offset, sizeof(header));
    const char *name = bytes + offset + sizeof(header);
    size_t nameLength = header.len ? strnlen(name, header.len) : 0;
    offset += sizeof(header) + header.len;
    if (offset > length) {
      break;
    }
    if (header.mask & IN_Q_OVERFLOW) {
      [_messages addObject:@"Too many changes at once: some were not recorded"];
      continue;
    }
    NSNumber *watch = [NSNumber numberWithInt:header.wd];
    NSData *directory = [_paths objectForKey:watch];
    if (header.mask & IN_IGNORED) {
      [_paths removeObjectForKey:watch];
      continue;
    }
    if (!directory) {
      continue;
    }
    if (header.mask & IN_DELETE_SELF) {
      if ([self isRoot:directory]) {
        [_messages addObject:[NSString stringWithFormat:@"%@ was removed; its changes are no longer recorded", LDDisplayPath(directory)]];
      }
      continue;
    }
    if (nameLength == 0) {
      continue;
    }
    NSData *path = LDJoinPath(directory, name, nameLength);
    BOOL isDirectory = (header.mask & IN_ISDIR) != 0;
    if (header.mask & IN_CREATE) {
      [events addObject:[self eventForPath:path action:LDFileWatcherActionCreated directory:isDirectory time:time]];
      if (isDirectory) {
        [_directoriesCreated addObject:path];
      }
    } else if (header.mask & IN_DELETE) {
      [events addObject:[self eventForPath:path action:LDFileWatcherActionDeleted directory:isDirectory time:time]];
    } else if (header.mask & IN_MODIFY) {
      // WinDirStat ignores modifications of folders; their children report.
      if (!isDirectory) {
        [events addObject:[self eventForPath:path action:LDFileWatcherActionModified directory:NO time:time]];
      }
    } else if (header.mask & IN_MOVED_FROM) {
      [movedFrom setObject:@[[self eventForPath:path action:LDFileWatcherActionRenamedOld directory:isDirectory time:time], path]
                    forKey:[NSNumber numberWithUnsignedInt:header.cookie]];
    } else if (header.mask & IN_MOVED_TO) {
      NSNumber *cookie = [NSNumber numberWithUnsignedInt:header.cookie];
      NSArray *from = [movedFrom objectForKey:cookie];
      if (from) {
        [movedFrom removeObjectForKey:cookie];
        if (isDirectory) {
          [self renameWatchedPath:[from objectAtIndex:1] to:path];
        }
        [events addObject:[from objectAtIndex:0]];
        [events addObject:[self eventForPath:path action:LDFileWatcherActionRenamedNew directory:isDirectory time:time]];
      } else {
        [events addObject:[self eventForPath:path action:LDFileWatcherActionCreated directory:isDirectory time:time]];
        if (isDirectory) {
          [_directoriesMovedIn addObject:path];
        }
      }
    }
  }

  return events;
}

- (BOOL)hasPendingMoves
{
  return [_pendingMovedFrom count] > 0;
}

- (NSArray *)flushPendingMovesBefore:(NSTimeInterval)time
{
  _watchesToRemove = [NSMutableArray array];
  NSMutableArray *events = [NSMutableArray array];
  for (NSNumber *cookie in [_pendingMovedFrom allKeys]) {
    LDFileWatcherEvent *renamed = [[_pendingMovedFrom objectForKey:cookie] objectAtIndex:0];
    if ([renamed time] >= time) {
      continue;
    }
    [_pendingMovedFrom removeObjectForKey:cookie];
    // Moved out of the watched trees: gone as far as the scan is concerned.
    [events addObject:[LDFileWatcherEvent eventWithPathData:[renamed pathData]
                                                    action:LDFileWatcherActionDeleted
                                                      time:[renamed time]
                                               logicalSize:0
                                               isDirectory:[renamed isDirectory]]];
    if ([renamed isDirectory]) {
      NSArray *watches = [self watchesAtOrBelowPath:[renamed pathData]];
      [_watchesToRemove addObjectsFromArray:watches];
      [_paths removeObjectsForKeys:watches];
    }
  }
  return events;
}

- (NSArray *)directoriesCreated { return _directoriesCreated ?: @[]; }
- (NSArray *)directoriesMovedIn { return _directoriesMovedIn ?: @[]; }
- (NSArray *)watchesToRemove { return _watchesToRemove ?: @[]; }
- (NSArray *)messages { return _messages ?: @[]; }

@end

// The inotify descriptor, its read source and the translator; everything
// below runs on the sink's serial queue.
@interface LDInotifyBackend : NSObject
{
@public
  int _fd;
  dispatch_source_t _source;
  LDInotifyTranslator *_translator;
  LDFileWatcherSink *_sink;
  BOOL _limitReported;
  BOOL _limitReached;
  volatile BOOL _stopped;
  BOOL _moveFlushScheduled;
}
@end

@implementation LDInotifyBackend

- (NSString *)watchLimitMessage
{
  int limit = 0;
  FILE *file = fopen("/proc/sys/fs/inotify/max_user_watches", "r");
  if (file) {
    if (fscanf(file, "%d", &limit) != 1) {
      limit = 0;
    }
    fclose(file);
  }
  NSString *setting = limit > 0 ? [NSString stringWithFormat:@" (fs.inotify.max_user_watches = %d)", limit] : @"";
  return [NSString stringWithFormat:@"Watch limit reached%@: changes in some folders are not recorded", setting];
}

// Returns NO when the system's watch limit stops it.
- (BOOL)addWatchForDirectory:(NSData *)path
{
  if (_limitReached) {
    return NO;
  }
  NSMutableData *terminated = [path mutableCopy];
  [terminated appendBytes:"\0" length:1];
  int watch = inotify_add_watch(_fd, [terminated bytes], LDInotifyMask);
  if (watch >= 0) {
    [_translator setPath:path forWatch:watch];
    return YES;
  }
  if (errno == ENOSPC) {
    _limitReached = YES;
    if (!_limitReported) {
      _limitReported = YES;
      [_sink reportMessage:[self watchLimitMessage]];
    }
    return NO;
  }
  return YES;
}

// Watches path and every folder below it on the same filesystem, without
// following symbolic links. With reportContents, what is found counts as
// created (it appeared before the watch could see it).
- (void)watchTreeAtPath:(NSData *)root reportContents:(BOOL)reportContents
{
  NSMutableData *terminated = [root mutableCopy];
  [terminated appendBytes:"\0" length:1];
  struct stat rootInfo;
  if (lstat([terminated bytes], &rootInfo) != 0 || !S_ISDIR(rootInfo.st_mode)) {
    return;
  }
  NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  while ([queue count] > 0 && !_stopped) {
    @autoreleasepool {
      NSData *directory = [queue lastObject];
      [queue removeLastObject];
      if (![self addWatchForDirectory:directory]) {
        return;
      }
      NSMutableData *directoryBytes = [directory mutableCopy];
      [directoryBytes appendBytes:"\0" length:1];
      int dirfd = open([directoryBytes bytes], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
      DIR *handle = dirfd >= 0 ? fdopendir(dirfd) : NULL;
      if (!handle) {
        if (dirfd >= 0) {
          close(dirfd);
        }
        continue;
      }
      struct dirent *entry;
      while ((entry = readdir(handle)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
          continue;
        }
        struct stat info;
        if (fstatat(dirfd, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
          continue;
        }
        NSData *path = LDJoinPath(directory, entry->d_name, strlen(entry->d_name));
        BOOL isDirectory = S_ISDIR(info.st_mode);
        if (reportContents) {
          [_sink addEvent:[LDFileWatcherEvent eventWithPathData:path
                                                         action:LDFileWatcherActionCreated
                                                           time:now
                                                    logicalSize:isDirectory ? 0 : (unsigned long long)info.st_size
                                                    isDirectory:isDirectory]];
        }
        if (isDirectory && info.st_dev == rootInfo.st_dev) {
          [queue addObject:path];
        }
      }
      closedir(handle);
    }
  }
}

- (void)readEvents
{
  // inotify_event is aligned for its int and uint32_t fields.
  char buffer[64 * 1024] __attribute__((aligned(__alignof__(struct inotify_event))));
  while (!_stopped) {
    ssize_t length = read(_fd, buffer, sizeof(buffer));
    if (length <= 0) {
      break;
    }
    NSArray *events = [_translator eventsForBuffer:buffer length:(size_t)length time:[[NSDate date] timeIntervalSince1970]];
    for (NSNumber *watch in [_translator watchesToRemove]) {
      inotify_rm_watch(_fd, [watch intValue]);
    }
    for (LDFileWatcherEvent *event in events) {
      [_sink addEvent:event];
    }
    for (NSString *message in [_translator messages]) {
      [_sink reportMessage:message];
    }
    for (NSData *directory in [_translator directoriesMovedIn]) {
      [self watchTreeAtPath:directory reportContents:NO];
    }
    for (NSData *directory in [_translator directoriesCreated]) {
      [self watchTreeAtPath:directory reportContents:YES];
    }
  }
  if ([_translator hasPendingMoves]) {
    [self scheduleMoveFlush];
  }
}

// A moved-from event whose moved-to has not arrived after a short wait was
// a move out of the watched trees.
static const NSTimeInterval LDMovePairingWait = 0.1;

- (void)scheduleMoveFlush
{
  if (_moveFlushScheduled) {
    return;
  }
  _moveFlushScheduled = YES;
  __weak LDInotifyBackend *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(LDMovePairingWait * NSEC_PER_SEC)), [_sink queue], ^{
    LDInotifyBackend *backend = weakSelf;
    if (!backend || backend->_stopped) {
      return;
    }
    backend->_moveFlushScheduled = NO;
    NSTimeInterval cutoff = [[NSDate date] timeIntervalSince1970] - LDMovePairingWait;
    NSArray *events = [backend->_translator flushPendingMovesBefore:cutoff];
    for (NSNumber *watch in [backend->_translator watchesToRemove]) {
      inotify_rm_watch(backend->_fd, [watch intValue]);
    }
    for (LDFileWatcherEvent *event in events) {
      [backend->_sink addEvent:event];
    }
    if ([backend->_translator hasPendingMoves]) {
      [backend scheduleMoveFlush];
    }
  });
}

@end

@implementation LDFileWatcher (Platform)

+ (BOOL)platformIsSupported
{
  return YES;
}

- (id)platformStartWatchingRoots:(NSArray *)roots sink:(LDFileWatcherSink *)sink error:(NSError **)error
{
  int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (fd < 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The file watcher could not start: %s", strerror(errno)]}];
    }
    return nil;
  }
  LDInotifyBackend *backend = [[LDInotifyBackend alloc] init];
  backend->_fd = fd;
  backend->_sink = sink;
  backend->_translator = [[LDInotifyTranslator alloc] initWithRootPaths:roots];

  // Each root is watched here, so a bad root fails now; the folders below
  // are added in the background.
  NSMutableArray *watchedRoots = [NSMutableArray array];
  int lastError = ENOENT;
  for (NSData *root in roots) {
    NSMutableData *terminated = [root mutableCopy];
    [terminated appendBytes:"\0" length:1];
    int watch = inotify_add_watch(fd, [terminated bytes], LDInotifyMask);
    if (watch >= 0) {
      [backend->_translator setPath:root forWatch:watch];
      [watchedRoots addObject:root];
    } else {
      lastError = errno;
    }
  }
  if ([watchedRoots count] == 0) {
    close(fd);
    if (error) {
      NSString *reason = lastError == ENOSPC ? [backend watchLimitMessage] : [NSString stringWithUTF8String:strerror(lastError)];
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:lastError userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The file watcher could not start: %@", reason]}];
    }
    return nil;
  }

  dispatch_queue_t queue = [sink queue];
  dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, queue);
  backend->_source = source;
  __weak LDInotifyBackend *weakBackend = backend;
  dispatch_source_set_event_handler(source, ^{
    [weakBackend readEvents];
  });
  dispatch_source_set_cancel_handler(source, ^{
    close(fd);
  });
  dispatch_async(queue, ^{
    LDInotifyBackend *strongBackend = weakBackend;
    for (NSData *root in watchedRoots) {
      [strongBackend watchTreeAtPath:root reportContents:NO];
    }
  });
  dispatch_resume(source);
  return backend;
}

- (void)platformStopWatching:(id)backend
{
  LDInotifyBackend *inotify = backend;
  inotify->_stopped = YES;
  if (inotify->_source) {
    dispatch_source_cancel(inotify->_source);
    inotify->_source = nil;
  }
}

@end

#endif
