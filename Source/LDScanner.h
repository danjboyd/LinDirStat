#import <Foundation/Foundation.h>
#import "LDFileNode.h"

#include <pthread.h>
#include <sys/types.h>

@class LDScanSession;

// Scans a directory tree. Directories are read by a pool of worker threads
// (WinDirStat uses several threads per drive); each directory is read by one
// worker, which is the only writer of that directory node's children.
@interface LDScanner : NSObject
{
  NSMutableSet *_visitedHardLinks;
  NSMutableSet *_visitedDirectories;
  NSMutableDictionary *_internedExtensionKeys;
  pthread_mutex_t _sharedStateLock;
  NSCondition *_workCondition;
  NSMutableArray *_pendingDirectories;
  NSMutableArray *_arenas;
  NSUInteger _activeWorkers;
  dev_t _rootDevice;
  BOOL _crossesFilesystems;
  LDSizeMetric _sortMetric;
  NSUInteger _threadCount;
  NSMutableArray *_retiredArrays;
}

// Scans path (following a symlink at the root). The root is published to the
// session as soon as it exists, and directories' children as they are read,
// so the tree can be displayed live; see -[LDDirectoryNode publishChildren:].
- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session;

// Scans one entry of an existing tree again (Refresh Selected). pathData is
// the entry's exact path; the result is a detached node with the same name,
// or nil if the entry no longer exists. Like the entry's original scan, a
// directory on another filesystem than its parent is not entered.
- (LDFileNode *)scanEntryAtPathData:(NSData *)pathData session:(LDScanSession *)session;

// Children arrays the final sort replaced. Readers of a live tree may still
// hold them, so they must be released on the main thread.
- (NSArray *)takeRetiredArrays;

// When NO (the default) directories on another filesystem than the scan root
// are recorded as mount points and not descended into, so scanning "/" does
// not wander into /proc, /sys or network mounts.
- (BOOL)crossesFilesystems;
- (void)setCrossesFilesystems:(BOOL)crossesFilesystems;

// Metric used to sort the finished tree (physical by default).
- (LDSizeMetric)sortMetric;
- (void)setSortMetric:(LDSizeMetric)sortMetric;

// Number of directories read concurrently (default 4, like WinDirStat's
// default threads per drive). 1 scans on the calling thread only.
+ (NSUInteger)defaultThreadCount;
- (NSUInteger)threadCount;
- (void)setThreadCount:(NSUInteger)threadCount;

- (BOOL)shouldDescendIntoDevice:(dev_t)device;

@end
