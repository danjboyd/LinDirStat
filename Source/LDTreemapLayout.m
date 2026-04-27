#import "LDTreemapLayout.h"
#import "LDFileNode.h"
#import "LDExtensionStats.h"
#import "LDTreemapItem.h"

#include <float.h>

@implementation LDTreemapLayout

+ (NSArray *)layoutItemsForRootNode:(LDFileNode *)rootNode inRect:(NSRect)rect
{
  NSMutableArray *items = [NSMutableArray array];
  [self appendNode:rootNode inRect:rect depth:0 toItems:items];
  return items;
}

+ (void)appendNode:(LDFileNode *)node inRect:(NSRect)rect depth:(NSUInteger)depth toItems:(NSMutableArray *)items
{
  if (!node || [node aggregateSize] == 0 || rect.size.width <= 0.0 || rect.size.height <= 0.0) {
    return;
  }

  if ([node kind] != LDFileNodeKindDirectory || [[node children] count] == 0) {
    NSString *extensionKey = [LDExtensionStats extensionKeyForFilename:[node displayName]];
    [items addObject:[LDTreemapItem itemWithNode:node rect:rect extensionKey:extensionKey depth:depth]];
    return;
  }

  NSArray *children = [[node children] sortedArrayUsingSelector:@selector(compareByAggregateSizeThenName:)];
  NSMutableArray *remaining = [NSMutableArray array];
  NSEnumerator *filterEnumerator = [children objectEnumerator];
  LDFileNode *filterChild = nil;
  while ((filterChild = [filterEnumerator nextObject])) {
    if ([filterChild aggregateSize] > 0) {
      [remaining addObject:filterChild];
    }
  }
  [self layoutChildren:remaining inRect:rect depth:depth toItems:items];
}

+ (double)areaForNodes:(NSArray *)nodes inRect:(NSRect)rect
{
  unsigned long long total = 0;
  NSEnumerator *enumerator = [nodes objectEnumerator];
  LDFileNode *node = nil;
  while ((node = [enumerator nextObject])) {
    total += [node aggregateSize];
  }
  return total > 0 ? (rect.size.width * rect.size.height) / (double)total : 0.0;
}

+ (double)worstAspectForRow:(NSArray *)row scale:(double)scale side:(double)side
{
  if ([row count] == 0 || side <= 0.0 || scale <= 0.0) {
    return DBL_MAX;
  }

  double sum = 0.0;
  double minArea = DBL_MAX;
  double maxArea = 0.0;
  NSEnumerator *enumerator = [row objectEnumerator];
  LDFileNode *node = nil;
  while ((node = [enumerator nextObject])) {
    double area = (double)[node aggregateSize] * scale;
    sum += area;
    minArea = MIN(minArea, area);
    maxArea = MAX(maxArea, area);
  }
  if (sum <= 0.0 || minArea <= 0.0) {
    return DBL_MAX;
  }
  double sideSquared = side * side;
  return MAX((sideSquared * maxArea) / (sum * sum),
             (sum * sum) / (sideSquared * minArea));
}

+ (void)layoutChildren:(NSMutableArray *)nodes inRect:(NSRect)rect depth:(NSUInteger)depth toItems:(NSMutableArray *)items
{
  if ([nodes count] == 0 || rect.size.width <= 0.0 || rect.size.height <= 0.0) {
    return;
  }

  double scale = [self areaForNodes:nodes inRect:rect];
  NSRect remainingRect = rect;
  NSMutableArray *row = [NSMutableArray array];

  while ([nodes count] > 0) {
    LDFileNode *candidate = [nodes objectAtIndex:0];
    double side = MIN(remainingRect.size.width, remainingRect.size.height);
    double currentWorst = [self worstAspectForRow:row scale:scale side:side];
    NSMutableArray *testRow = [NSMutableArray arrayWithArray:row];
    [testRow addObject:candidate];
    double testWorst = [self worstAspectForRow:testRow scale:scale side:side];
    if ([row count] == 0 || testWorst <= currentWorst) {
      [row addObject:candidate];
      [nodes removeObjectAtIndex:0];
    } else {
      remainingRect = [self layoutRow:row inRect:remainingRect scale:scale depth:depth toItems:items];
      [row removeAllObjects];
    }
  }

  if ([row count] > 0) {
    [self layoutRow:row inRect:remainingRect scale:scale depth:depth toItems:items];
  }
}

+ (NSRect)layoutRow:(NSArray *)row inRect:(NSRect)rect scale:(double)scale depth:(NSUInteger)depth toItems:(NSMutableArray *)items
{
  double areaSum = 0.0;
  NSEnumerator *areaEnumerator = [row objectEnumerator];
  LDFileNode *areaNode = nil;
  while ((areaNode = [areaEnumerator nextObject])) {
    areaSum += (double)[areaNode aggregateSize] * scale;
  }
  if (areaSum <= 0.0) {
    return rect;
  }

  BOOL horizontal = rect.size.width >= rect.size.height;
  double offset = horizontal ? rect.origin.y : rect.origin.x;
  double thickness = horizontal ? areaSum / rect.size.height : areaSum / rect.size.width;
  NSEnumerator *enumerator = [row objectEnumerator];
  LDFileNode *child = nil;
  NSUInteger index = 0;
  while ((child = [enumerator nextObject])) {
    double childArea = (double)[child aggregateSize] * scale;
    NSRect childRect = rect;
    if (horizontal) {
      double height = (index == [row count] - 1) ? NSMaxY(rect) - offset : childArea / thickness;
      childRect.origin.y = offset;
      childRect.size.height = height;
      childRect.size.width = thickness;
      offset += height;
    } else {
      double width = (index == [row count] - 1) ? NSMaxX(rect) - offset : childArea / thickness;
      childRect.origin.x = offset;
      childRect.size.width = width;
      childRect.size.height = thickness;
      offset += width;
    }

    [self appendNode:child inRect:childRect depth:depth + 1 toItems:items];
    index++;
  }

  if (horizontal) {
    rect.origin.x += thickness;
    rect.size.width -= thickness;
  } else {
    rect.origin.y += thickness;
    rect.size.height -= thickness;
  }
  return rect;
}

+ (id)itemAtPoint:(NSPoint)point inItems:(NSArray *)items
{
  LDTreemapItem *best = nil;
  NSEnumerator *enumerator = [items objectEnumerator];
  LDTreemapItem *item = nil;
  while ((item = [enumerator nextObject])) {
    if (NSPointInRect(point, [item rect]) && (!best || [item depth] >= [best depth])) {
      best = item;
    }
  }
  return best;
}

@end
