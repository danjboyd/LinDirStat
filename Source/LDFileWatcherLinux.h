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
  NSMutableDictionary *_pendingMovedFrom;
}

- (id)initWithRootPaths:(NSArray *)roots;
- (void)setPath:(NSData *)path forWatch:(int)watch;
- (NSData *)pathForWatch:(int)watch;
- (void)forgetWatch:(int)watch;
- (NSUInteger)watchCount;
// Watches of path and everything below it.
- (NSArray *)watchesAtOrBelowPath:(NSData *)path;

// Translates one read() of an inotify descriptor. The two halves of a
// rename can arrive in separate reads, so a moved-from event is held back
// until its moved-to arrives (a rename) or -flushPendingMovesBefore: gives
// up on it (a move out of the watched trees: Deleted). A moved-to without
// a held moved-from was a move into the trees: Created.
- (NSArray *)eventsForBuffer:(const void *)buffer length:(size_t)length time:(NSTimeInterval)time;

// Moved-from events still waiting for their other half.
- (BOOL)hasPendingMoves;
// Turns held moved-from events older than time into deletions, dropping
// the watches of folders that left; -watchesToRemove reports those.
- (NSArray *)flushPendingMovesBefore:(NSTimeInterval)time;

// Results of the last call: folders to watch, recursively (created ones have
// their contents reported as created, since they may have filled before the
// watch started), watch descriptors to drop (NSNumber), and messages.
- (NSArray *)directoriesCreated;
- (NSArray *)directoriesMovedIn;
- (NSArray *)watchesToRemove;
- (NSArray *)messages;

@end

#endif
