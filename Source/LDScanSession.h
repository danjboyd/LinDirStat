#import <Foundation/Foundation.h>
#import "LDFileNode.h"

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
  LDFileNode *_rootNode;
  volatile BOOL _canceled;
  volatile BOOL _asyncFinished;
  NSString *_asyncPath;
  LDSizeMetric _sortMetric;
  NSUInteger _threadCount;
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

- (NSTimeInterval)elapsedTime;

- (LDFileNode *)rootNode;
- (void)setRootNode:(LDFileNode *)rootNode;

// Metric used to sort the finished tree on the scanning thread.
- (LDSizeMetric)sortMetric;
- (void)setSortMetric:(LDSizeMetric)sortMetric;

- (void)markScanning;
- (void)markComplete;
- (void)markFailed;
- (void)cancel;
- (BOOL)isCanceled;
- (BOOL)isFinished;
// Number of directories read concurrently (see -[LDScanner threadCount]).
- (NSUInteger)threadCount;
- (void)setThreadCount:(NSUInteger)threadCount;

// Scans on a libdispatch queue. completion, if given, runs on the main queue
// once the tree is complete (or the scan was canceled).
- (void)startAsyncScanPath:(NSString *)path;
- (void)startAsyncScanPath:(NSString *)path completion:(void (^)(void))completion;
// Scans one entry of an existing tree again (see -[LDScanner
// scanEntryAtPathData:session:]). completion runs on the main queue with the
// detached replacement node, or nil if the entry is gone.
- (void)startAsyncRefreshOfPathData:(NSData *)pathData completion:(void (^)(LDFileNode *node))completion;
- (BOOL)waitUntilFinishedBeforeDate:(NSDate *)deadline;
- (NSDictionary *)snapshotDictionary;

@end
