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
  NSUInteger _activeWorkers;
  dev_t _rootDevice;
  BOOL _crossesFilesystems;
  LDSizeMetric _sortMetric;
  NSUInteger _threadCount;
}

- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session;

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
