#import <Foundation/Foundation.h>
#import "LDFileNode.h"

#include <pthread.h>
#include <sys/types.h>

@class LDScanSession;
@class LDScanOptions;
@class LDPathFilter;
@class LDDuplicateCollector;
@class LDHardLinkTable;

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
  LDScanOptions *_options;
  LDPathFilter *_folderFilter;
  LDPathFilter *_fileFilter;
  LDSizeMetric _sortMetric;
  NSUInteger _threadCount;
  NSMutableArray *_retiredArrays;
  LDDuplicateCollector *_duplicateCollector;
  LDHardLinkTable *_hardLinks;
  LDFileNode *_replacedNode;
  BOOL _usesGivenHardLinks;
  BOOL _attachesHardLinks;
  NSTimeInterval _readDuration;
  NSTimeInterval _finishDuration;
}

// Scans path (following a symlink at the root). The root is published to the
// session as soon as it exists, and directories' children as they are read,
// so the tree can be displayed live; see -[LDDirectoryNode publishChildren:].
- (LDFileNode *)scanPath:(NSString *)path session:(LDScanSession *)session;

// Scans several paths with one worker pool. One path is the same as
// -scanPath:session:. Otherwise the result is an LDComputerNode whose
// children are full-path roots, published (with the computer node as the
// session root) before any directory is read; it stays scan-pending until
// every root is done. Hard links are counted once across all roots, and each
// root is its own filesystem for the mount-point rule.
- (LDFileNode *)scanPaths:(NSArray *)paths session:(LDScanSession *)session;

// Scans one entry of an existing tree again (Refresh Selected). pathData is
// the entry's exact path; the result is a detached node with the same name,
// or nil if the entry no longer exists (or the options now exclude it). Like
// the entry's original scan, a directory on another filesystem than its
// parent is not entered, so rescan a root of a multi-root scan with
// -scanPath:session: instead.
- (LDFileNode *)scanEntryAtPathData:(NSData *)pathData session:(LDScanSession *)session;

// Files with several links are recorded in a hard-link table (see
// LDHardLinks.h). A fresh scan makes one, attaches it to its root and, if
// the options process hard links, builds the "<Hardlinks>" folders. A
// refresh passes the tree's table instead, with the node it rescans: links
// below that node do not count as already seen, and nothing is built (the
// caller updates the tree once the result is in place).
- (void)setHardLinkTable:(LDHardLinkTable *)table replacing:(LDFileNode *)node;
// The table of the last scan.
- (LDHardLinkTable *)hardLinkTable;

// Children arrays the final sort replaced. Readers of a live tree may still
// hold them, so they must be released on the main thread.
- (NSArray *)takeRetiredArrays;

// Seconds the last scan spent reading directories, and totalling and
// sorting the tree afterwards (for profiling).
- (NSTimeInterval)readDuration;
- (NSTimeInterval)finishDuration;

// Filters and exclusions (default: [[LDScanOptions alloc] init]). Setting
// them also sets threadCount to theirs.
- (LDScanOptions *)scanOptions;
- (void)setScanOptions:(LDScanOptions *)options;

// The inverse of the options' excludeMountPoints. When NO (the default)
// directories on another filesystem than their scan root are recorded as
// mount points and not descended into, so scanning "/" does not wander into
// /proc, /sys or network mounts.
- (BOOL)crossesFilesystems;
- (void)setCrossesFilesystems:(BOOL)crossesFilesystems;

// The options' findsDuplicates. When YES, -scanPath:session: and
// -scanPaths:session: feed every directory's files to the session's
// duplicate collector (made if the session has none) and finish adding
// when the scan is done; hashing goes on after they return. Entry rescans
// never look for duplicates. When NO the scan does no duplicate work.
- (BOOL)findsDuplicates;
- (void)setFindsDuplicates:(BOOL)findsDuplicates;

// Metric used to sort the finished tree (physical by default).
- (LDSizeMetric)sortMetric;
- (void)setSortMetric:(LDSizeMetric)sortMetric;

// Number of directories read concurrently (default 4, like WinDirStat's
// default threads per drive). 1 scans on the calling thread only.
+ (NSUInteger)defaultThreadCount;
- (NSUInteger)threadCount;
- (void)setThreadCount:(NSUInteger)threadCount;

- (BOOL)shouldDescendIntoDevice:(dev_t)device rootDevice:(dev_t)rootDevice;

@end
