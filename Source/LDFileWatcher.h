#import <Foundation/Foundation.h>

// WinDirStat's File Watcher (Controls/FileWatcherControl.cpp): reports what
// changes on disk below the scan roots, recursively, while it runs. The
// platform backend lives in LDFileWatcherLinux.m (inotify) and
// LDFileWatcherApple.m (FSEvents); this file is the portable interface.

// WinDirStat's IDS_WATCHER_VERBS, in its order.
typedef enum {
  LDFileWatcherActionCreated = 1,
  LDFileWatcherActionDeleted,
  LDFileWatcherActionModified,
  LDFileWatcherActionRenamedOld,
  LDFileWatcherActionRenamedNew
} LDFileWatcherAction;

@interface LDFileWatcherEvent : NSObject
{
  NSData *_pathData;
  LDFileWatcherAction _action;
  NSTimeInterval _time;
  unsigned long long _logicalSize;
  BOOL _directory;
}

// path is the full path's exact bytes; time is seconds since 1970;
// logicalSize is the item's size when the event was read (0 once it is gone).
+ (LDFileWatcherEvent *)eventWithPathData:(NSData *)path
                                   action:(LDFileWatcherAction)action
                                     time:(NSTimeInterval)time
                              logicalSize:(unsigned long long)logicalSize
                              isDirectory:(BOOL)isDirectory;
- (NSData *)pathData;
// The path for display (invalid UTF-8 shown with replacement characters).
- (NSString *)path;
- (LDFileWatcherAction)action;
- (NSTimeInterval)time;
- (unsigned long long)logicalSize;
- (BOOL)isDirectory;

// "Created", "Deleted", "Modified", "Renamed (Old)", "Renamed (New)".
+ (NSString *)titleForAction:(LDFileWatcherAction)action;

@end

// WinDirStat 2.7's File Watcher quick filter (329f9c91,
// CFileWatcherControl::SetQuickFilter): a case-insensitive regular
// expression searched for anywhere in an event's full path. POSIX extended,
// as LinDirStat's Search, not ECMAScript.
@interface LDFileWatcherPathFilter : NSObject
{
  void *_regex;
}
// nil when pattern is not a valid expression; an empty pattern matches
// every path.
+ (LDFileWatcherPathFilter *)filterWithPattern:(NSString *)pattern;
- (BOOL)matchesEvent:(LDFileWatcherEvent *)event;
@end

@interface LDFileWatcher : NSObject
{
  NSArray *_roots;
  void (^_eventHandler)(NSArray *events);
  void (^_messageHandler)(NSString *message);
  id _sink;
  id _backend;
}

// NO when this platform has no backend yet.
+ (BOOL)isSupported;

// roots are the exact bytes of the folders to watch, each recursively.
- (id)initWithRootPaths:(NSArray *)roots;
- (NSArray *)rootPaths;

// Events arrive on the main queue in batches (a few per second at most), in
// the order they happened. Set both handlers before starting.
- (void)setEventHandler:(void (^)(NSArray *events))handler;
// Problems that do not stop the watcher (events lost to a queue overflow,
// the system's watch limit, a watched root removed) arrive on the main
// queue as one-line messages.
- (void)setMessageHandler:(void (^)(NSString *message))handler;

// Starts watching in the background; returns NO with an error when nothing
// can be watched (unsupported platform, no root can be opened). Never
// blocks on the size of the trees.
- (BOOL)startWithError:(NSError **)error;
// Stops; no handler is called after this returns.
- (void)stop;
- (BOOL)isRunning;

// The most rows the File Watcher list keeps; older ones are dropped.
+ (NSUInteger)maximumListedEvents;

@end
