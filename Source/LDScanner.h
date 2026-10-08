#import <Foundation/Foundation.h>
#import "LDFileNode.h"

#include <sys/types.h>

@class LDScanSession;

@interface LDScanner : NSObject
{
  NSMutableSet *_visitedHardLinks;
  NSMutableSet *_visitedDirectories;
  NSMutableDictionary *_internedExtensionKeys;
  dev_t _rootDevice;
  BOOL _crossesFilesystems;
  LDSizeMetric _sortMetric;
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

- (BOOL)shouldDescendIntoDevice:(dev_t)device;

@end
