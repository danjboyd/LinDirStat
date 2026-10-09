#import "LDLargestFiles.h"
#import "LDNodeRanking.h"

@implementation LDLargestFiles

+ (BOOL)isRankableFile:(LDFileNode *)node
{
  LDFileNodeKind kind = [node kind];
  if (kind == LDFileNodeKindDirectory || kind == LDFileNodeKindSpecial) {
    return NO;
  }
  return [node error] == LDFileNodeErrorNone;
}

+ (NSArray *)largestFilesUnderNode:(LDFileNode *)root count:(NSUInteger)count
{
  if (count == 0 || !root) {
    return [NSArray array];
  }
  LDTopNodeCollector *collector = [[LDTopNodeCollector alloc] initWithLimit:count];
  LDVisitNodes(root, ^(LDFileNode *node) {
    if ([self isRankableFile:node]) {
      [collector offerNode:node size:[node size]];
    }
  });
  return [collector sortedNodes];
}

@end
