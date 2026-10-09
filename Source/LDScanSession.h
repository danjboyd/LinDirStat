#import <Foundation/Foundation.h>
#import "LDFileNode.h"

@class LDScanOptions;
@class LDDuplicateCollector;
@class LDHardLinkTable;
@class LDScanResults;
@class LDScanResultsRequest;

typedef enum {
  LDScanSessionStateIdle = 0,
  LDScanSessionStateScanning = 1,
  LDScanSessionStateComplete = 2,
  LDScanSessionStateCanceled = 3,
  LDScanSessionStateFailed = 4
} LDScanSessionState;

// Scan state shared between the scanning thread and the main thread. Every
// accessor is safe to call from either thread.
@interface LDScanSession : NSObject
{
  NSLock *_lock;
  volatile LDScanSessionState _state;
  NSString *_currentPath;
  volatile NSUInteger _skippedCount;
  volatile NSUInteger _errorCount;
  volatile NSUInteger _filesScanned;
  volatile NSUInteger _directoriesScanned;
  volatile unsigned long long _bytesScanned;
  NSDate *_startedAt;
  NSDate *_finishedAt;
  NSDate *_suspendedAt;
  NSTimeInterval _suspendedDuration;
  NSCondition *_suspendCondition;
  volatile BOOL _suspended;
  LDFileNode *_rootNode;
  volatile BOOL _canceled;
  volatile BOOL _asyncFinished;
  LDSizeMetric _sortMetric;
  NSUInteger _threadCount;
  LDScanOptions *_scanOptions;
  LDDuplicateCollector *_duplicateCollector;
  LDHardLinkTable *_hardLinkTable;
  LDFileNode *_replacedNode;
  LDScanResultsRequest *_resultsRequest;
  LDScanResults *_results;
  NSTimeInterval _readDuration;
  NSTimeInterval _finishDuration;
  NSTimeInterval _resultsDuration;
}

- (LDScanSessionState)state;
- (NSString *)currentPath;
- (void)setCurrentPath:(NSString *)currentPath;
- (NSUInteger)skippedCount;
- (NSUInteger)errorCount;
- (void)incrementSkippedCount;
- (void)incrementErrorCount;

// Live progress counters, updated as entries are read.
- (NSUInteger)filesScanned;
- (NSUInteger)directoriesScanned;
- (unsigned long long)bytesScanned;
- (void)recordFileWithBytes:(unsigned long long)bytes;
- (void)recordDirectory;
// Batched form used by scanner workers, once per directory read.
- (void)recordFiles:(NSUInteger)files directories:(NSUInteger)directories bytes:(unsigned long long)bytes;

// Wall-clock scan time, not counting time spent suspended.
- (NSTimeInterval)elapsedTime;

- (LDFileNode *)rootNode;
- (void)setRootNode:(LDFileNode *)rootNode;

// Metric used to sort the finished tree on the scanning thread.
- (LDSizeMetric)sortMetric;
- (void)setSortMetric:(LDSizeMetric)sortMetric;

// Finds duplicates while the scan runs when the scan options ask for it
// (scans of whole paths only, not refreshes). Created when such a scan
// starts; it keeps hashing after the scan is complete, and -cancel cancels
// it too.
- (LDDuplicateCollector *)duplicateCollector;
- (void)setDuplicateCollector:(LDDuplicateCollector *)collector;

// When set before a scan starts, the scanning thread works out the results
// the views need once the tree is final (see LDScanResults.h); -results then
// returns them in the completion block. Not used for entry rescans.
- (LDScanResultsRequest *)resultsRequest;
- (void)setResultsRequest:(LDScanResultsRequest *)request;
- (LDScanResults *)results;

// For profiling: seconds spent reading directories, totalling and sorting
// the tree, and working out -results.
- (NSTimeInterval)readDuration;
- (NSTimeInterval)finishDuration;
- (NSTimeInterval)resultsDuration;

- (void)markScanning;
- (void)markComplete;
- (void)markFailed;
- (void)cancel;
- (BOOL)isCanceled;
- (BOOL)isFinished;

// Suspend pauses the scan's workers between directory reads (they block,
// they do not spin) until -resume or -cancel.
- (void)suspend;
- (void)resume;
- (BOOL)isSuspended;
// Called by scanner workers: returns once the session is not suspended or
// has been canceled.
- (void)waitWhileSuspended;

// Number of directories read concurrently (see -[LDScanner threadCount]).
- (NSUInteger)threadCount;
- (void)setThreadCount:(NSUInteger)threadCount;
// Filters and exclusions for the async scans and entry rescans. Setting them
// also sets threadCount to theirs. nil (the default) means default options.
- (LDScanOptions *)scanOptions;
- (void)setScanOptions:(LDScanOptions *)options;

// For the entry rescans: the tree's hard-link table and the node being
// rescanned (see -[LDScanner setHardLinkTable:replacing:]).
- (void)setHardLinkTable:(LDHardLinkTable *)table replacing:(LDFileNode *)node;

// Scans on a libdispatch queue. completion, if given, runs on the main queue
// once the tree is complete (or the scan was canceled).
- (void)startAsyncScanPath:(NSString *)path;
- (void)startAsyncScanPath:(NSString *)path completion:(void (^)(void))completion;
// Scans several paths under a "This Computer" root (see -[LDScanner
// scanPaths:session:]).
- (void)startAsyncScanPaths:(NSArray *)paths completion:(void (^)(void))completion;
// Scans one entry of an existing tree again (see -[LDScanner
// scanEntryAtPathData:session:]). completion runs on the main queue with the
// detached replacement node, or nil if the entry is gone.
- (void)startAsyncRefreshOfPathData:(NSData *)pathData completion:(void (^)(LDFileNode *node))completion;
// Scans a scan root (a volume under "This Computer") again; the result
// keeps its full path and its own filesystem, like the original root.
- (void)startAsyncRescanOfRootPath:(NSString *)path completion:(void (^)(LDFileNode *node))completion;
- (BOOL)waitUntilFinishedBeforeDate:(NSDate *)deadline;
- (NSDictionary *)snapshotDictionary;

@end
