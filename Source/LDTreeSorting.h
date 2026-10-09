#import <Foundation/Foundation.h>
#import "LDFileNode.h"

// Column sort orders for the directory tree. The treemap needs children in
// descending size order, so the tree view sorts copies with these instead of
// reordering the model.
typedef enum {
  LDTreeSortKeyName = 0,
  LDTreeSortKeyPhysicalSize,
  LDTreeSortKeyLogicalSize,
  LDTreeSortKeyFiles,
  LDTreeSortKeyFolders,
  LDTreeSortKeyLastChange,
  LDTreeSortKeyItems
} LDTreeSortKey;

@interface LDTreeSorting : NSObject

// Ties fall back to descending physical size, then name.
+ (NSArray *)sortedNodes:(NSArray *)nodes byKey:(LDTreeSortKey)key ascending:(BOOL)ascending;

// WinDirStat's default direction: ascending for Name and Last Change,
// descending for the numeric columns.
+ (BOOL)defaultAscendingForKey:(LDTreeSortKey)key;

@end
