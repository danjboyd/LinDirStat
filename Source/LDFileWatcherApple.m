#import "LDFileWatcher+Backend.h"
#import "LDLocalization.h"

#if defined(__APPLE__)

#import <CoreServices/CoreServices.h>

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

// The FSEvents backend. One stream watches every root recursively at file
// level and delivers on the sink's queue. FSEvents reports canonical paths
// (/private/var/... for /var/...), so each event is mapped back to the root
// as it was given. It also merges the flags of nearby changes to one path,
// so what is reported is decided from the flags and whether the path still
// exists: a path that is gone was deleted, one that exists was created or
// modified. Renames arrive as two events with the same file ID, old path
// first, possibly with other events between them; an unpaired rename is a
// move into or out of the watched folders.
//
// Known limit: fseventsd hands over changes some milliseconds late, so a
// file changed in the moment before watching starts can be reported as
// Modified.
@class LDPendingRename;

@interface LDFSEventsBackend : NSObject
{
@public
  FSEventStreamRef _stream;
  LDFileWatcherSink *_sink;
  // Parallel arrays: the canonical root and the root as given.
  NSArray *_canonicalRoots;
  NSArray *_givenRoots;
  BOOL _stopped;
  // When watching began; items born earlier were not created now.
  struct timespec _started;
  // First halves of renames by file ID, waiting for their second halves.
  NSMutableDictionary *_pendingRenames;
  // The flags last seen for each path. FSEvents keeps accumulating a path's
  // flags for a while, so only flags new since its previous event count.
  NSMutableDictionary *_lastFlags;
}
@end

@implementation LDFSEventsBackend
@end

static NSData *LDTerminatedBytes(NSData *path)
{
  NSMutableData *terminated = [path mutableCopy];
  [terminated appendBytes:"\0" length:1];
  return terminated;
}

static NSData *LDCanonicalRoot(NSData *root)
{
  char resolved[PATH_MAX];
  if (realpath([LDTerminatedBytes(root) bytes], resolved) == NULL) {
    return nil;
  }
  return [NSData dataWithBytes:resolved length:strlen(resolved)];
}

// The path as the watcher's roots spell it.
static NSData *LDGivenPath(LDFSEventsBackend *backend, const char *path)
{
  size_t length = strlen(path);
  NSUInteger count = [backend->_canonicalRoots count];
  for (NSUInteger i = 0; i < count; i++) {
    NSData *canonical = [backend->_canonicalRoots objectAtIndex:i];
    size_t rootLength = [canonical length];
    if (length >= rootLength && memcmp(path, [canonical bytes], rootLength) == 0
        && (length == rootLength || path[rootLength] == '/' || (rootLength == 1 && path[0] == '/'))) {
      NSMutableData *given = [[backend->_givenRoots objectAtIndex:i] mutableCopy];
      if (rootLength == 1) {
        // The root is "/": keep the whole path after the given root.
        if ([given length] > 1) {
          [given appendBytes:path length:length];
        } else {
          [given setData:[NSData dataWithBytes:path length:length]];
        }
      } else {
        [given appendBytes:path + rootLength length:length - rootLength];
      }
      return given;
    }
  }
  return [NSData dataWithBytes:path length:length];
}

static void LDAddEvent(LDFSEventsBackend *backend, NSData *path, LDFileWatcherAction action,
                       BOOL exists, const struct stat *info, BOOL isDirectory, NSTimeInterval now)
{
  unsigned long long size = (exists && !isDirectory) ? (unsigned long long)info->st_size : 0;
  [backend->_sink addEvent:[LDFileWatcherEvent eventWithPathData:path
                                                          action:action
                                                            time:now
                                                     logicalSize:size
                                                     isDirectory:isDirectory]];
}

// One half of a rename waiting for its partner, which may come in the next
// callback.
@interface LDPendingRename : NSObject
{
@public
  NSData *_path;
  NSNumber *_fileID;
  BOOL _directory;
  BOOL _exists;
  struct stat _info;
}
@end

@implementation LDPendingRename
@end

// A rename with no partner moved an item into or out of the watched folders.
static void LDFlushPendingRename(LDFSEventsBackend *backend, LDPendingRename *pending, NSTimeInterval now)
{
  if ([backend->_pendingRenames objectForKey:pending->_fileID] != pending) {
    return;
  }
  [backend->_pendingRenames removeObjectForKey:pending->_fileID];
  LDAddEvent(backend, pending->_path, pending->_exists ? LDFileWatcherActionCreated : LDFileWatcherActionDeleted,
             pending->_exists, &pending->_info, pending->_directory, now);
}

static BOOL LDBornBeforeWatching(LDFSEventsBackend *backend, const struct stat *info)
{
  const struct timespec *birth = &info->st_birthtimespec;
  return birth->tv_sec < backend->_started.tv_sec
    || (birth->tv_sec == backend->_started.tv_sec && birth->tv_nsec < backend->_started.tv_nsec);
}

static void LDStreamCallback(ConstFSEventStreamRef stream, void *info, size_t count, void *eventPaths,
                             const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[])
{
  (void)stream;
  (void)ids;
  LDFSEventsBackend *backend = (__bridge LDFSEventsBackend *)info;
  if (backend->_stopped) {
    return;
  }
  NSArray *events = (__bridge NSArray *)eventPaths;
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  BOOL reportedOverflow = NO;

  for (size_t i = 0; i < count; i++) {
    FSEventStreamEventFlags flag = flags[i];
    NSDictionary *event = [events objectAtIndex:i];
    NSString *pathString = [event objectForKey:(__bridge NSString *)kFSEventStreamEventExtendedDataPathKey];
    NSNumber *fileID = [event objectForKey:(__bridge NSString *)kFSEventStreamEventExtendedFileIDKey];
    const char *rawPath = [pathString fileSystemRepresentation];

    if (flag & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped)) {
      if (!reportedOverflow) {
        [backend->_sink reportMessage:LDLocalized(@"Some changes were missed because too many happened at once")];
        reportedOverflow = YES;
      }
      continue;
    }
    if (flag & kFSEventStreamEventFlagRootChanged) {
      [backend->_sink reportMessage:[NSString stringWithFormat:LDLocalized(@"%@ was moved or deleted"), pathString]];
      continue;
    }
    if (!rawPath || (flag & kFSEventStreamEventFlagHistoryDone)) {
      continue;
    }

    NSData *path = LDGivenPath(backend, rawPath);
    NSNumber *previous = [backend->_lastFlags objectForKey:path];
    if ([backend->_lastFlags count] > 10000) {
      [backend->_lastFlags removeAllObjects];
    }
    [backend->_lastFlags setObject:@(flag) forKey:path];
    FSEventStreamEventFlags fresh = flag & ~(FSEventStreamEventFlags)[previous unsignedIntValue];
    struct stat st;
    memset(&st, 0, sizeof(st));
    BOOL exists = lstat(rawPath, &st) == 0;
    BOOL isDirectory = exists ? S_ISDIR(st.st_mode) : (flag & kFSEventStreamEventFlagItemIsDir) != 0;
    BOOL created = (fresh & kFSEventStreamEventFlagItemCreated) != 0;
    BOOL removed = (flag & kFSEventStreamEventFlagItemRemoved) != 0;
    BOOL modified = (fresh & kFSEventStreamEventFlagItemModified) != 0 && !isDirectory;
    BOOL renamed = (flag & kFSEventStreamEventFlagItemRenamed) != 0;
    // FSEvents can deliver changes made just before the stream started, and
    // its flags accumulate: an item that existed before watching was not
    // created now.
    if (created && exists && LDBornBeforeWatching(backend, &st)) {
      created = NO;
    }

    if (renamed) {
      LDPendingRename *pending = fileID ? [backend->_pendingRenames objectForKey:fileID] : nil;
      if (pending) {
        // The second half: the new name. What happened to it afterwards
        // follows the rename.
        [backend->_pendingRenames removeObjectForKey:fileID];
        LDAddEvent(backend, pending->_path, LDFileWatcherActionRenamedOld, NO, NULL, pending->_directory, now);
        LDAddEvent(backend, path, LDFileWatcherActionRenamedNew, exists, &st, isDirectory, now);
        if (modified && exists) {
          LDAddEvent(backend, path, LDFileWatcherActionModified, YES, &st, NO, now);
        }
        if (removed && !exists) {
          LDAddEvent(backend, path, LDFileWatcherActionDeleted, NO, NULL, isDirectory, now);
        }
        continue;
      }
      // The first half: the old name, which existed before the rename (a
      // Created flag on it is history). A change to it came before the rename.
      if (modified) {
        LDAddEvent(backend, path, LDFileWatcherActionModified, exists, &st, NO, now);
      }
      LDPendingRename *half = [[LDPendingRename alloc] init];
      half->_path = path;
      half->_fileID = fileID ? fileID : (id)[NSNull null];
      half->_directory = isDirectory;
      half->_exists = exists;
      half->_info = st;
      if (!fileID) {
        LDAddEvent(backend, path, exists ? LDFileWatcherActionCreated : LDFileWatcherActionDeleted,
                   exists, &st, isDirectory, now);
        continue;
      }
      LDPendingRename *earlier = [backend->_pendingRenames objectForKey:fileID];
      if (earlier) {
        LDFlushPendingRename(backend, earlier, now);
      }
      [backend->_pendingRenames setObject:half forKey:fileID];
      // Other changes can come between the halves, or the partner in a later
      // callback; give it 100 ms.
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), [backend->_sink queue], ^{
        if (!backend->_stopped) {
          LDFlushPendingRename(backend, half, [[NSDate date] timeIntervalSince1970]);
        }
      });
      continue;
    }
    if (created && (exists || removed)) {
      LDAddEvent(backend, path, LDFileWatcherActionCreated, exists, &st, isDirectory, now);
    }
    // Folder modifications are not reported, as in WinDirStat; a new file's
    // writes are part of its creation.
    if (modified && !(created && exists)) {
      LDAddEvent(backend, path, LDFileWatcherActionModified, exists, &st, NO, now);
    }
    if (removed && !exists) {
      LDAddEvent(backend, path, LDFileWatcherActionDeleted, NO, NULL, isDirectory, now);
    }
  }
}

@implementation LDFileWatcher (Platform)

+ (BOOL)platformIsSupported
{
  return YES;
}

- (id)platformStartWatchingRoots:(NSArray *)roots sink:(LDFileWatcherSink *)sink error:(NSError **)error
{
  NSMutableArray *canonicalRoots = [NSMutableArray array];
  NSMutableArray *givenRoots = [NSMutableArray array];
  NSMutableArray *streamPaths = [NSMutableArray array];
  for (NSData *root in roots) {
    struct stat info;
    NSData *canonical = LDCanonicalRoot(root);
    if (!canonical || stat([LDTerminatedBytes(canonical) bytes], &info) != 0 || !S_ISDIR(info.st_mode)) {
      continue;
    }
    // Longest canonical root first, so nested roots map to the closest one.
    NSUInteger index = 0;
    while (index < [canonicalRoots count] && [[canonicalRoots objectAtIndex:index] length] >= [canonical length]) {
      index++;
    }
    [canonicalRoots insertObject:canonical atIndex:index];
    [givenRoots insertObject:root atIndex:index];
    NSString *string = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:[canonical bytes]
                                                                                   length:[canonical length]];
    [streamPaths addObject:string];
  }
  if ([streamPaths count] == 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:@{
        NSLocalizedDescriptionKey: @"None of the folders can be watched"}];
    }
    return nil;
  }

  LDFSEventsBackend *backend = [[LDFSEventsBackend alloc] init];
  backend->_sink = sink;
  backend->_canonicalRoots = canonicalRoots;
  backend->_givenRoots = givenRoots;
  clock_gettime(CLOCK_REALTIME, &backend->_started);
  backend->_pendingRenames = [NSMutableDictionary dictionary];
  backend->_lastFlags = [NSMutableDictionary dictionary];
  // The stream holds the backend through its context.
  FSEventStreamContext context = {0, (__bridge void *)backend, CFRetain, CFRelease, NULL};
  FSEventStreamCreateFlags flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
    | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
    | kFSEventStreamCreateFlagUseExtendedData;
  FSEventStreamRef stream = FSEventStreamCreate(kCFAllocatorDefault, LDStreamCallback, &context,
                                                (__bridge CFArrayRef)streamPaths,
                                                kFSEventStreamEventIdSinceNow, 0.05, flags);
  if (!stream) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:@{
        NSLocalizedDescriptionKey: @"The folders could not be watched"}];
    }
    return nil;
  }
  FSEventStreamSetDispatchQueue(stream, [sink queue]);
  if (!FSEventStreamStart(stream)) {
    FSEventStreamInvalidate(stream);
    FSEventStreamRelease(stream);
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EIO userInfo:@{
        NSLocalizedDescriptionKey: @"The folders could not be watched"}];
    }
    return nil;
  }
  backend->_stream = stream;
  return backend;
}

- (void)platformStopWatching:(id)state
{
  LDFSEventsBackend *backend = state;
  if (!backend || !backend->_stream) {
    return;
  }
  FSEventStreamRef stream = backend->_stream;
  backend->_stream = NULL;
  dispatch_async([backend->_sink queue], ^{
    backend->_stopped = YES;
    FSEventStreamStop(stream);
    FSEventStreamInvalidate(stream);
    FSEventStreamRelease(stream);
  });
}

@end

#endif
