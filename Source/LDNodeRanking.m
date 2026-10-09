#import "LDNodeRanking.h"

#include <stdlib.h>
#include <string.h>

enum { LDInlineChainLength = 64 };

typedef struct {
  LDFileNode * __unsafe_unretained *nodes;
  NSUInteger count;
  LDFileNode * __unsafe_unretained inlineNodes[LDInlineChainLength];
} LDAncestorChain;

// nodes[0] is the node itself, nodes[count - 1] its root.
static void LDChainInit(LDAncestorChain *chain, LDFileNode *node)
{
  NSUInteger count = [node depth] + 1;
  chain->nodes = chain->inlineNodes;
  if (count > LDInlineChainLength) {
    chain->nodes = (LDFileNode * __unsafe_unretained *)calloc(count, sizeof(LDFileNode *));
  }
  chain->count = count;
  LDFileNode *cursor = node;
  for (NSUInteger index = 0; index < count; index++) {
    chain->nodes[index] = cursor;
    cursor = [cursor parent];
  }
}

static void LDChainFree(LDAncestorChain *chain)
{
  if (chain->nodes != chain->inlineNodes) {
    free((void *)chain->nodes);
  }
}

// Yields the bytes of "name1/name2/.../nameN" for a top-down list of nodes.
typedef struct {
  LDFileNode * __unsafe_unretained *nodes;
  NSInteger index;
  const char *cursor;
} LDPathCursor;

static int LDPathCursorNext(LDPathCursor *cursor)
{
  if (*cursor->cursor != '\0') {
    return (unsigned char)*cursor->cursor++;
  }
  if (cursor->index <= 0) {
    return -1;
  }
  cursor->index--;
  cursor->cursor = [cursor->nodes[cursor->index] nameBytes];
  return '/';
}

static NSComparisonResult LDCompareData(NSData *left, NSData *right)
{
  NSUInteger leftLength = [left length];
  NSUInteger rightLength = [right length];
  int result = memcmp([left bytes], [right bytes], MIN(leftLength, rightLength));
  if (result != 0) {
    return result < 0 ? NSOrderedAscending : NSOrderedDescending;
  }
  if (leftLength == rightLength) {
    return NSOrderedSame;
  }
  return leftLength < rightLength ? NSOrderedAscending : NSOrderedDescending;
}

static NSComparisonResult LDCompareChainsBelowCommonAncestor(LDAncestorChain *left, LDAncestorChain *right)
{
  NSUInteger leftRemaining = left->count;
  NSUInteger rightRemaining = right->count;
  while (leftRemaining > 0 && rightRemaining > 0
         && left->nodes[leftRemaining - 1] == right->nodes[rightRemaining - 1]) {
    leftRemaining--;
    rightRemaining--;
  }
  // Both paths continue the shared prefix with the same separator, so the
  // comparison starts at the first name below the common ancestor.
  if (leftRemaining == 0 || rightRemaining == 0) {
    if (leftRemaining == rightRemaining) {
      return NSOrderedSame;
    }
    return leftRemaining == 0 ? NSOrderedAscending : NSOrderedDescending;
  }
  LDPathCursor leftCursor = { left->nodes, (NSInteger)leftRemaining - 1, [left->nodes[leftRemaining - 1] nameBytes] };
  LDPathCursor rightCursor = { right->nodes, (NSInteger)rightRemaining - 1, [right->nodes[rightRemaining - 1] nameBytes] };
  for (;;) {
    int leftByte = LDPathCursorNext(&leftCursor);
    int rightByte = LDPathCursorNext(&rightCursor);
    if (leftByte != rightByte) {
      return leftByte < rightByte ? NSOrderedAscending : NSOrderedDescending;
    }
    if (leftByte < 0) {
      return NSOrderedSame;
    }
  }
}

NSComparisonResult LDCompareNodePaths(LDFileNode *left, LDFileNode *right)
{
  if (left == right) {
    return NSOrderedSame;
  }
  LDAncestorChain leftChain;
  LDAncestorChain rightChain;
  LDChainInit(&leftChain, left);
  LDChainInit(&rightChain, right);
  NSComparisonResult result;
  if (leftChain.nodes[leftChain.count - 1] == rightChain.nodes[rightChain.count - 1]) {
    result = LDCompareChainsBelowCommonAncestor(&leftChain, &rightChain);
  } else {
    result = LDCompareData([left pathData], [right pathData]);
  }
  LDChainFree(&leftChain);
  LDChainFree(&rightChain);
  return result;
}

void LDVisitNodes(LDFileNode *root, void (^visitor)(LDFileNode *node))
{
  if (!root) {
    return;
  }
  visitor(root);
  if ([root kind] != LDFileNodeKindDirectory) {
    return;
  }
  for (LDFileNode *child in [root children]) {
    LDVisitNodes(child, visitor);
  }
}

typedef struct {
  __unsafe_unretained LDFileNode *node;
  unsigned long long size;
} LDRankedNode;

// Larger size first, then smaller path.
static NSComparisonResult LDCompareRanked(const LDRankedNode *left, const LDRankedNode *right)
{
  if (left->size != right->size) {
    return left->size > right->size ? NSOrderedAscending : NSOrderedDescending;
  }
  return LDCompareNodePaths(left->node, right->node);
}

static int LDCompareRankedForSort(const void *left, const void *right)
{
  return (int)LDCompareRanked(left, right);
}

@implementation LDTopNodeCollector

- (id)initWithLimit:(NSUInteger)limit
{
  self = [super init];
  if (self) {
    _limit = limit;
  }
  return self;
}

- (void)dealloc
{
  free(_entries);
}

- (LDRankedNode *)entries
{
  return (LDRankedNode *)_entries;
}

- (void)growIfNeeded
{
  if (_count < _capacity) {
    return;
  }
  NSUInteger capacity = _capacity ? _capacity * 2 : 64;
  if (_limit != NSUIntegerMax && capacity > _limit) {
    capacity = _limit;
  }
  _entries = realloc(_entries, capacity * sizeof(LDRankedNode));
  _capacity = capacity;
}

// The heap keeps its worst entry at index 0 so it can be replaced cheaply.
- (BOOL)entryAtIndex:(NSUInteger)left isWorseThanIndex:(NSUInteger)right
{
  LDRankedNode *entries = [self entries];
  return LDCompareRanked(&entries[left], &entries[right]) == NSOrderedDescending;
}

- (void)swapIndex:(NSUInteger)left withIndex:(NSUInteger)right
{
  LDRankedNode *entries = [self entries];
  LDRankedNode saved = entries[left];
  entries[left] = entries[right];
  entries[right] = saved;
}

- (void)siftUpFromIndex:(NSUInteger)index
{
  while (index > 0) {
    NSUInteger parent = (index - 1) / 2;
    if (![self entryAtIndex:index isWorseThanIndex:parent]) {
      return;
    }
    [self swapIndex:index withIndex:parent];
    index = parent;
  }
}

- (void)siftDownFromIndex:(NSUInteger)index
{
  for (;;) {
    NSUInteger worst = index;
    NSUInteger left = index * 2 + 1;
    NSUInteger right = left + 1;
    if (left < _count && [self entryAtIndex:left isWorseThanIndex:worst]) {
      worst = left;
    }
    if (right < _count && [self entryAtIndex:right isWorseThanIndex:worst]) {
      worst = right;
    }
    if (worst == index) {
      return;
    }
    [self swapIndex:index withIndex:worst];
    index = worst;
  }
}

- (void)offerNode:(LDFileNode *)node size:(unsigned long long)size
{
  _offeredCount++;
  if (_limit == 0) {
    return;
  }
  LDRankedNode candidate = { node, size };
  if (_count == _limit) {
    if (LDCompareRanked(&candidate, &[self entries][0]) != NSOrderedAscending) {
      return;
    }
    [self entries][0] = candidate;
    [self siftDownFromIndex:0];
    return;
  }
  [self growIfNeeded];
  [self entries][_count] = candidate;
  _count++;
  if (_limit != NSUIntegerMax) {
    [self siftUpFromIndex:_count - 1];
  }
}

- (NSUInteger)offeredCount
{
  return _offeredCount;
}

- (NSArray *)sortedNodes
{
  LDRankedNode *entries = [self entries];
  if (_count > 1) {
    qsort(entries, _count, sizeof(LDRankedNode), LDCompareRankedForSort);
  }
  NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:_count];
  for (NSUInteger index = 0; index < _count; index++) {
    [nodes addObject:entries[index].node];
  }
  if (_limit != NSUIntegerMax) {
    // Sorting broke the heap order; restore it so offers can continue.
    for (NSUInteger index = _count / 2; index-- > 0;) {
      [self siftDownFromIndex:index];
    }
  }
  return nodes;
}

@end
