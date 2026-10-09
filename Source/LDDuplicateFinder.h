#import <Foundation/Foundation.h>
#import "LDFileNode.h"

#include <pthread.h>

// One row group of WinDirStat's Duplicates tab (ItemDupe.cpp): files with
// the same size and contents.
@interface LDDuplicateGroup : NSObject
{
  NSString *_hashString;
  unsigned long long _logicalSize;
  unsigned long long _totalPhysicalSize;
  NSArray *_nodes;
  NSString *_extensionsLabel;
}

- (id)initWithHashString:(NSString *)hashString
             logicalSize:(unsigned long long)logicalSize
                   nodes:(NSArray *)nodes
       totalPhysicalSize:(unsigned long long)totalPhysicalSize;

// 32 lowercase hex characters: SHA-512 truncated to 16 bytes.
- (NSString *)hashString;
// Logical size of each file in the group.
- (unsigned long long)logicalSize;
// Sorted by path bytes.
- (NSArray *)nodes;
- (NSUInteger)count;
- (unsigned long long)totalLogicalSize;
- (unsigned long long)totalPhysicalSize;
// "(.jpg, .png)": unique extensions in first-seen order, ".???" for none,
// cut at about 128 characters with an ellipsis. Main thread only.
- (NSString *)extensionsLabel;

@end

// WinDirStat's duplicate detection (FileDupeControl.cpp). Regular files that
// stat cleanly and are not hard-link duplicates are bucketed by logical size;
// buckets of two or more are hashed in tiers (first 4 KiB, first 1 MiB,
// whole file) up to the tier their size needs, splitting on each digest.
// Files that cannot be read are dropped. There is no minimum size.
//
// Starting snapshots the candidate nodes and their paths on the calling
// thread; hashing then runs on a background queue and never reads the tree.
@interface LDDuplicateFinder : NSObject
{
  LDFileNode *_root;
  int _cancelled;
}

- (id)initWithRootNode:(LDFileNode *)root;

// Both blocks run on the main queue; progress at most ten times a second,
// with hashedFiles counting candidates whose verdict is final. Neither runs
// after -cancel. Groups are sorted by total physical size, largest first.
- (void)startWithProgress:(void (^)(NSUInteger hashedFiles, NSUInteger candidateFiles))progress
               completion:(void (^)(NSArray *groups))completion;
- (void)cancel;
- (BOOL)isCancelled;

// Synchronous variant of the above, for tests and scripts.
- (NSArray *)findGroups;

// Drops files equal to or below any of nodes, then groups left with fewer
// than two files. Used after a refresh or delete.
+ (NSArray *)groups:(NSArray *)groups removingNodesUnder:(NSArray *)nodes;

@end

// WinDirStat's duplicate detection during the scan (FileDupeControl.cpp:
// files are bucketed by size as they are found, and a bucket is hashed as
// soon as it holds two files). Scanner workers add each directory's
// published children; buckets of two or more are hashed on a low-priority
// queue with LDDuplicateFinder's tiers, so the result is the same as
// running LDDuplicateFinder on the finished tree. A size seen once costs
// one table slot, not an object.
@interface LDDuplicateCollector : NSObject
{
  pthread_mutex_t _lock;
  pthread_cond_t _finishedCondition;
  struct LDSizeSlot *_slots;
  NSUInteger _slotMask;
  NSUInteger _slotsUsed;
  LDNameArena *_names;
  NSMutableArray *_buckets;
  NSMutableArray *_dirtyBuckets;
  NSArray *_finalGroups;
  void (^_updateHandler)(NSArray *groups, BOOL finished);
  BOOL _draining;
  BOOL _addingFinished;
  BOOL _finished;
  BOOL _notificationScheduled;
  int _cancelled;
}

// Called by scanner workers with a directory's published children (their
// paths must be complete). Anything but regular files that stat cleanly and
// are not hard-link duplicates is ignored. Thread-safe.
- (void)addNodes:(NSArray *)nodes;
// No more nodes will be added; finishes once hashing is done.
- (void)finishAdding;
// Stops hashing; it finishes at once with the groups found so far.
- (void)cancel;
- (BOOL)isCancelled;
- (BOOL)isFinished;
- (void)waitUntilFinished;

// The groups so far (all of them once finished), sorted like
// -[LDDuplicateFinder findGroups].
- (NSArray *)groups;

// handler runs on the main queue with -groups when they change, at most
// about twice a second, and once more with finished YES. Setting it
// reports the current state.
- (void)setUpdateHandler:(void (^)(NSArray *groups, BOOL finished))handler;

@end
