#import "LDFileWatcher+Backend.h"

#if defined(__APPLE__)

#include <errno.h>

// STUB: the FSEvents backend is still to be written (parity plan M8). Until
// then the File Watcher is unsupported on macOS and its menu item disabled.
// The backend should watch every root recursively (kFSEventStreamCreateFlag
// FileEvents | WatchRoot), deliver on [sink queue], map item flags to the
// LDFileWatcherAction values (paired renames to Renamed (Old)/(New), a
// rename whose path no longer exists to Deleted), skip folder modifications
// as WinDirStat does, and report kFSEventStreamEventFlagMustScanSubDirs or
// dropped events with -[LDFileWatcherSink reportMessage:].
@implementation LDFileWatcher (Platform)

+ (BOOL)platformIsSupported
{
  return NO;
}

- (id)platformStartWatchingRoots:(NSArray *)roots sink:(LDFileWatcherSink *)sink error:(NSError **)error
{
  (void)roots;
  (void)sink;
  if (error) {
    *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOTSUP userInfo:@{
      NSLocalizedDescriptionKey: @"The file watcher is not available on this system yet"}];
  }
  return nil;
}

- (void)platformStopWatching:(id)backend
{
  (void)backend;
}

@end

#endif
