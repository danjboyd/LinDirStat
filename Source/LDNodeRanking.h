#import <Foundation/Foundation.h>
#import "LDFileNode.h"

// Compares the full paths of two nodes byte by byte, as -pathData would,
// without building either path: only the parts below their deepest common
// ancestor are walked. Nodes from different trees fall back to -pathData.
FOUNDATION_EXPORT NSComparisonResult LDCompareNodePaths(LDFileNode *left, LDFileNode *right);

// Calls visitor for root and every node below it, parents before children.
FOUNDATION_EXPORT void LDVisitNodes(LDFileNode *root, void (^visitor)(LDFileNode *node));

// Keeps the limit best nodes offered to it, best meaning larger size first,
// then smaller path. Memory and work are O(limit) per collector and
// O(log limit) per offer. Nodes are not retained while collecting, so the
// tree must stay alive until -sortedNodes returns.
@interface LDTopNodeCollector : NSObject
{
  void *_entries;
  NSUInteger _count;
  NSUInteger _capacity;
  NSUInteger _limit;
  NSUInteger _offeredCount;
}

// NSUIntegerMax keeps every node.
- (id)initWithLimit:(NSUInteger)limit;
- (void)offerNode:(LDFileNode *)node size:(unsigned long long)size;
// Every node offered so far, kept or not.
- (NSUInteger)offeredCount;
// The kept nodes, best first.
- (NSArray *)sortedNodes;

@end
