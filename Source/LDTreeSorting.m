#import "LDTreeSorting.h"

typedef struct {
  LDTreeSortKey key;
  BOOL ascending;
} LDSortSpec;

static NSComparisonResult LDCompareValues(unsigned long long left, unsigned long long right)
{
  if (left < right) {
    return NSOrderedAscending;
  }
  return left > right ? NSOrderedDescending : NSOrderedSame;
}

// WinDirStat's item types in their order (Item.h ITEMTYPE): This Computer,
// volumes, folders, then files and everything else.
static NSUInteger LDTypeRank(LDFileNode *node)
{
  if ([node isComputer]) {
    return 0;
  }
  if ([[node parent] isComputer]) {
    return 1;
  }
  return [node kind] == LDFileNodeKindDirectory ? 2 : 3;
}

static NSComparisonResult LDCompareNodes(id leftObject, id rightObject, void *context)
{
  LDSortSpec *spec = context;
  LDFileNode *left = leftObject;
  LDFileNode *right = rightObject;
  NSComparisonResult result = NSOrderedSame;
  switch (spec->key) {
    case LDTreeSortKeyName:
      // By type first (IX CompareSibling), then name.
      result = LDCompareValues(LDTypeRank(left), LDTypeRank(right));
      if (result == NSOrderedSame) {
        result = [[left displayName] caseInsensitiveCompare:[right displayName]];
      }
      break;
    case LDTreeSortKeyPhysicalSize:
      result = LDCompareValues([left aggregateAllocatedSize], [right aggregateAllocatedSize]);
      break;
    case LDTreeSortKeyLogicalSize:
      result = LDCompareValues([left aggregateSize], [right aggregateSize]);
      break;
    case LDTreeSortKeyFiles:
      result = LDCompareValues([left fileCount], [right fileCount]);
      break;
    case LDTreeSortKeyFolders:
      result = LDCompareValues([left directoryCount], [right directoryCount]);
      break;
    case LDTreeSortKeyItems:
      result = LDCompareValues([left fileCount] + [left directoryCount], [right fileCount] + [right directoryCount]);
      break;
    case LDTreeSortKeyLastChange:
      result = LDCompareValues((unsigned long long)[left aggregateModificationTime],
                               (unsigned long long)[right aggregateModificationTime]);
      break;
  }
  if (!spec->ascending) {
    result = (NSComparisonResult)-result;
  }
  if (result == NSOrderedSame && spec->key != LDTreeSortKeyPhysicalSize) {
    result = LDCompareValues([right aggregateAllocatedSize], [left aggregateAllocatedSize]);
  }
  if (result == NSOrderedSame && spec->key != LDTreeSortKeyName) {
    result = [[left displayName] caseInsensitiveCompare:[right displayName]];
  }
  return result;
}

@implementation LDTreeSorting

+ (NSArray *)sortedNodes:(NSArray *)nodes byKey:(LDTreeSortKey)key ascending:(BOOL)ascending
{
  LDSortSpec spec = {key, ascending};
  return [nodes sortedArrayUsingFunction:LDCompareNodes context:&spec];
}

+ (BOOL)defaultAscendingForKey:(LDTreeSortKey)key
{
  return key == LDTreeSortKeyName || key == LDTreeSortKeyLastChange;
}

@end
