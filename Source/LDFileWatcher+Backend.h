#import "LDFileWatcher.h"
#include <dispatch/dispatch.h>

// What a platform backend of LDFileWatcher sees. A backend gets a sink when
// it starts, reports events and messages to it from the sink's queue, and
// the sink batches them onto the main queue for the watcher's handlers.
@interface LDFileWatcherSink : NSObject
{
  __weak LDFileWatcher *_watcher;
  dispatch_queue_t _queue;
  NSMutableArray *_pending;
  NSMutableDictionary *_lastIndexByPath;
  BOOL _flushScheduled;
}
// A serial queue for the backend's work; the sink's methods must be called
// on it.
- (dispatch_queue_t)queue;
// Repeated modifications of one item within a batch collapse into one row.
- (void)addEvent:(LDFileWatcherEvent *)event;
- (void)reportMessage:(NSString *)message;
@end

// Implemented once per platform (LDFileWatcherLinux.m, LDFileWatcherApple.m).
@interface LDFileWatcher (Platform)
+ (BOOL)platformIsSupported;
// Starts watching roots (exact path bytes) on [sink queue] and returns the
// backend's state, or nil with an error when no root can be watched.
- (id)platformStartWatchingRoots:(NSArray *)roots sink:(LDFileWatcherSink *)sink error:(NSError **)error;
// Stops the backend returned above; it may finish asynchronously. What it
// reports after this is dropped.
- (void)platformStopWatching:(id)backend;
@end
