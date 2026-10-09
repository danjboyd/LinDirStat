#import "LDFileWatcher.h"

#if !defined(__APPLE__)

// Turns raw inotify events into WinDirStat's watcher actions. It knows the
// folder of every watch descriptor, pairs renames by cookie, and says which
// watches the backend must add or remove; it never calls inotify itself.
@interface LDInotifyTranslator : NSObject
{
  NSMutableDictionary *_paths;
  NSMutableArray *_directoriesCreated;
  NSMutableArray *_directoriesMovedIn;
  NSMutableArray *_watchesToRemove;
  NSMutableArray *_messages;
  NSArray *_roots;
}

- (id)initWithRootPaths:(NSArray *)roots;
- (void)setPath:(NSData *)path forWatch:(int)watch;
- (NSData *)pathForWatch:(int)watch;
- (void)forgetWatch:(int)watch;
- (NSUInteger)watchCount;
// Watches of path and everything below it.
- (NSArray *)watchesAtOrBelowPath:(NSData *)path;

// Translates one read() of an inotify descriptor. A rename whose other half
// is not in the buffer was a move out of (Deleted) or into (Created) the
// watched trees.
- (NSArray *)eventsForBuffer:(const void *)buffer length:(size_t)length time:(NSTimeInterval)time;

// Results of the last call: folders to watch, recursively (created ones have
// their contents reported as created, since they may have filled before the
// watch started), watch descriptors to drop (NSNumber), and messages.
- (NSArray *)directoriesCreated;
- (NSArray *)directoriesMovedIn;
- (NSArray *)watchesToRemove;
- (NSArray *)messages;

@end

#endif
