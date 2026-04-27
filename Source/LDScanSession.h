#import <Foundation/Foundation.h>

@class LDFileNode;

typedef enum {
  LDScanSessionStateIdle = 0,
  LDScanSessionStateScanning = 1,
  LDScanSessionStateComplete = 2,
  LDScanSessionStateCanceled = 3,
  LDScanSessionStateFailed = 4
} LDScanSessionState;

@interface LDScanSession : NSObject
{
  LDScanSessionState _state;
  NSString *_currentPath;
  NSUInteger _skippedCount;
  NSUInteger _errorCount;
  NSDate *_startedAt;
  NSDate *_finishedAt;
  LDFileNode *_rootNode;
  BOOL _canceled;
  BOOL _asyncFinished;
  NSString *_asyncPath;
}

- (LDScanSessionState)state;
- (NSString *)currentPath;
- (void)setCurrentPath:(NSString *)currentPath;
- (NSUInteger)skippedCount;
- (NSUInteger)errorCount;
- (void)incrementSkippedCount;
- (void)incrementErrorCount;
- (LDFileNode *)rootNode;
- (void)setRootNode:(LDFileNode *)rootNode;
- (void)markScanning;
- (void)markComplete;
- (void)markFailed;
- (void)cancel;
- (BOOL)isCanceled;
- (void)startAsyncScanPath:(NSString *)path;
- (BOOL)waitUntilFinishedBeforeDate:(NSDate *)deadline;
- (NSDictionary *)snapshotDictionary;

@end
