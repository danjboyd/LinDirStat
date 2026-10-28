#import <Foundation/Foundation.h>
#import "LDFileNode.h"

// The extension key of the row that groups unregistered extensions.
FOUNDATION_EXPORT NSString *const LDExtensionGroupKey;

@interface LDExtensionStats : NSObject
{
  NSString *_extensionKey;
  NSString *_displayName;
  unsigned long long _bytes;
  unsigned long long _allocatedBytes;
  NSUInteger _fileCount;
  NSUInteger _colorIndex;
  NSSet *_groupedKeys;
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

// WinDirStat 2.8's Group Unregistered Types (04b336dc, RebuildExtensionData):
// colours stats (sorted by bytes for metric) by rank as above, but the
// extensions in grouped count as one entry, sized by their sum, that shares
// one colour. With grouped empty this is the plain ranking.
+ (void)assignColorsToSortedStats:(NSArray *)stats metric:(LDSizeMetric)metric grouping:(NSSet *)grouped;
// The extension list's rows: stats without the grouped extensions, plus one
// "…" row (LDExtensionGroupKey) totalling them, in its members' shared
// colour. stats itself when nothing is grouped.
+ (NSArray *)rowsForStats:(NSArray *)stats grouping:(NSSet *)grouped;

- (id)initWithExtensionKey:(NSString *)extensionKey;
- (NSString *)extensionKey;
// The "…" row and the extensions it totals (nil for other rows).
- (BOOL)isGroup;
- (NSSet *)groupedKeys;
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
