#import <Foundation/Foundation.h>
#import "LDFileNode.h"
#import "LDTreemapLayout.h"

// What the views need from a finished tree, worked out on the scanning
// thread right after the final sort, so the main thread does not walk a
// tree of millions of nodes when a scan completes (see docs/performance.md).
@interface LDScanResultsRequest : NSObject <NSCopying>
{
  LDSizeMetric _metric;
  NSUInteger _largestFileCount;
  int _treemapWidth;
  int _treemapHeight;
  LDTreemapOptions _treemapOptions;
}

+ (LDScanResultsRequest *)requestWithMetric:(LDSizeMetric)metric largestFileCount:(NSUInteger)count;
- (LDSizeMetric)metric;
- (NSUInteger)largestFileCount;
// Also lays out and renders the treemap at this size. 0 (the default) skips it.
- (void)setTreemapWidth:(int)width height:(int)height options:(LDTreemapOptions)options;
- (int)treemapWidth;
- (int)treemapHeight;
- (LDTreemapOptions)treemapOptions;

@end

@interface LDScanResults : NSObject
{
  LDFileNode *_rootNode;
  LDScanResultsRequest *_request;
  NSArray *_extensionStats;
  NSDictionary *_colorIndexes;
  NSArray *_largestFiles;
  LDTreemap *_treemap;
  NSData *_treemapPixels;
}

// Runs on any thread; root must not change meanwhile.
+ (LDScanResults *)resultsForRootNode:(LDFileNode *)root request:(LDScanResultsRequest *)request;

- (LDFileNode *)rootNode;
- (LDScanResultsRequest *)request;
// As +[LDExtensionStats sortedStatsForRootNode:metric:].
- (NSArray *)extensionStats;
// As +[LDExtensionStats colorIndexMapForSortedStats:].
- (NSDictionary *)colorIndexes;
// As +[LDLargestFiles largestFilesUnderNode:count:].
- (NSArray *)largestFiles;
// nil unless the request asked for a treemap.
- (LDTreemap *)treemap;
// RGBA from -[LDTreemap renderRGBAWithColorIndexes:] with -colorIndexes.
- (NSData *)treemapPixels;

@end
