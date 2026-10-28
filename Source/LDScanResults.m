#import "LDScanResults.h"
#import "LDExtensionStats.h"
#import "LDLargestFiles.h"

#include <dispatch/dispatch.h>

@implementation LDScanResultsRequest

+ (LDScanResultsRequest *)requestWithMetric:(LDSizeMetric)metric largestFileCount:(NSUInteger)count
{
  LDScanResultsRequest *request = [[LDScanResultsRequest alloc] init];
  request->_metric = metric;
  request->_largestFileCount = count;
  return request;
}

- (id)copyWithZone:(NSZone *)zone
{
  LDScanResultsRequest *copy = [[LDScanResultsRequest allocWithZone:zone] init];
  copy->_metric = _metric;
  copy->_largestFileCount = _largestFileCount;
  copy->_treemapWidth = _treemapWidth;
  copy->_treemapHeight = _treemapHeight;
  copy->_treemapOptions = _treemapOptions;
  return copy;
}

- (LDSizeMetric)metric { return _metric; }
- (NSUInteger)largestFileCount { return _largestFileCount; }
- (int)treemapWidth { return _treemapWidth; }
- (int)treemapHeight { return _treemapHeight; }
- (LDTreemapOptions)treemapOptions { return _treemapOptions; }

- (void)setTreemapWidth:(int)width height:(int)height options:(LDTreemapOptions)options
{
  _treemapWidth = MAX(0, width);
  _treemapHeight = MAX(0, height);
  _treemapOptions = options;
}

@end

@implementation LDScanResults

+ (LDScanResults *)resultsForRootNode:(LDFileNode *)root request:(LDScanResultsRequest *)request
{
  if (!root || !request) {
    return nil;
  }
  LDScanResults *results = [[LDScanResults alloc] init];
  results->_rootNode = root;
  results->_request = [request copy];
  LDSizeMetric metric = [request metric];
  int width = [request treemapWidth];
  int height = [request treemapHeight];
  // The treemap layout does not need the colors, so it runs alongside the
  // statistics walk.
  __block LDTreemap *treemap = nil;
  dispatch_group_t group = dispatch_group_create();
  // Folder headers need the view's font and the Auto grid colour its
  // theme, so such a treemap is laid out by the view.
  LDTreemapOptions treemapOptions = [request treemapOptions];
  if (width > 0 && height > 0 && !treemapOptions.showFolderFrames && treemapOptions.gridColor != LDTreemapGridColorAuto) {
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      treemap = [[LDTreemap alloc] initWithRootNode:root metric:metric width:width height:height
                                            options:[request treemapOptions]];
    });
  }
  NSArray *largest = nil;
  results->_extensionStats = [LDExtensionStats sortedStatsForRootNode:root
                                                               metric:metric
                                                         largestFiles:&largest
                                                                count:[request largestFileCount]];
  results->_largestFiles = largest;
  results->_colorIndexes = [LDExtensionStats colorIndexMapForSortedStats:results->_extensionStats];
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
  if (treemap) {
    results->_treemap = treemap;
    results->_treemapPixels = [treemap renderRGBAWithColorIndexes:results->_colorIndexes];
  }
  return results;
}

- (LDFileNode *)rootNode { return _rootNode; }
- (LDScanResultsRequest *)request { return _request; }
- (NSArray *)extensionStats { return _extensionStats; }
- (NSDictionary *)colorIndexes { return _colorIndexes; }
- (NSArray *)largestFiles { return _largestFiles; }
- (LDTreemap *)treemap { return _treemap; }
- (NSData *)treemapPixels { return _treemapPixels; }

@end
