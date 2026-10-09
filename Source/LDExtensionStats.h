#import <Foundation/Foundation.h>
#import "LDFileNode.h"

@interface LDExtensionStats : NSObject
{
  NSString *_extensionKey;
  NSString *_displayName;
  unsigned long long _bytes;
  unsigned long long _allocatedBytes;
  NSUInteger _fileCount;
  NSUInteger _colorIndex;
}

+ (NSString *)extensionKeyForFilename:(NSString *)filename;
// Sorted by logical bytes.
+ (NSArray *)sortedStatsForRootNode:(id)rootNode;
// Sorted by bytes for the metric, descending. Each entry's colorIndex is set
// from its rank, matching WinDirStat's legend: the largest types get distinct
// palette colors and the rest share the final (grey) palette entry.
+ (NSArray *)sortedStatsForRootNode:(id)rootNode metric:(LDSizeMetric)metric;
// As above, also returning in largestFiles (if not NULL) what
// +[LDLargestFiles largestFilesUnderNode:count:] would, from the same walk.
+ (NSArray *)sortedStatsForRootNode:(id)rootNode
                             metric:(LDSizeMetric)metric
                       largestFiles:(NSArray **)largestFiles
                              count:(NSUInteger)count;
// Maps extension key -> NSNumber palette index for the given sorted stats.
+ (NSDictionary *)colorIndexMapForSortedStats:(NSArray *)stats;

- (id)initWithExtensionKey:(NSString *)extensionKey;
- (NSString *)extensionKey;
- (NSString *)displayName;
// Logical bytes.
- (unsigned long long)bytes;
- (unsigned long long)allocatedBytes;
- (unsigned long long)bytesForMetric:(LDSizeMetric)metric;
- (NSUInteger)fileCount;
- (NSUInteger)colorIndex;
- (void)setColorIndex:(NSUInteger)colorIndex;
- (double)percentageOfTotal:(unsigned long long)totalBytes;
- (double)percentageOfTotal:(unsigned long long)totalBytes metric:(LDSizeMetric)metric;
- (void)addBytes:(unsigned long long)bytes;
- (void)addBytes:(unsigned long long)bytes allocatedBytes:(unsigned long long)allocatedBytes;

@end
