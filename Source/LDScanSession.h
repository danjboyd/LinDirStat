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
- (void)startAsyncScanPath:(NSString *)path;
- (BOOL)waitUntilFinishedBeforeDate:(NSDate *)deadline;
- (NSDictionary *)snapshotDictionary;

@end
