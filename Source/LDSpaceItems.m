#import "LDSpaceItems.h"
#import "LDVolumes.h"

@implementation LDSpaceItems

+ (BOOL)hasSpaceItems:(LDFileNode *)node
{
  return [self spaceItemOfKind:LDFileNodeKindFreeSpace inVolume:node] != nil
    || [self spaceItemOfKind:LDFileNodeKindUnknown inVolume:node] != nil;
}

+ (NSArray *)volumeNodesOfRoot:(LDFileNode *)root
{
  return [self volumeNodesOfRoot:root isVolumeRoot:^BOOL(LDFileNode *node) {
    return [LDVolumes isVolumeRootPathData:[node pathData]];
  }];
}

+ (NSArray *)volumeNodesOfRoot:(LDFileNode *)root isVolumeRoot:(BOOL (^)(LDFileNode *node))isVolumeRoot
{
  if (!root) {
    return @[];
  }
  NSArray *candidates = [root isComputer] ? [root children] : @[root];
  NSMutableArray *volumes = [NSMutableArray array];
  for (LDFileNode *node in candidates) {
    if ([node kind] != LDFileNodeKindDirectory) {
      continue;
    }
    if ([root isComputer] || [self hasSpaceItems:node] || isVolumeRoot(node)) {
      [volumes addObject:node];
    }
  }
  return volumes;
}

+ (LDFileNode *)spaceItemOfKind:(LDFileNodeKind)kind inVolume:(LDFileNode *)volume
{
  for (LDFileNode *child in [volume children]) {
    if ([child kind] == kind) {
      return child;
    }
  }
  return nil;
}

// What the scan found on the volume, without the space items.
+ (unsigned long long)talliedBytesOfVolume:(LDFileNode *)volume
{
  unsigned long long tallied = 0;
  for (LDFileNode *child in [volume children]) {
    if (![child isSpaceItem]) {
      tallied += [child aggregateAllocatedSize];
    }
  }
  return tallied;
}

+ (NSArray *)updateVolumes:(NSArray *)volumes
             showFreeSpace:(BOOL)showFreeSpace
               showUnknown:(BOOL)showUnknown
                     usage:(LDVolumeUsageQuery)usage
                    metric:(LDSizeMetric)metric
{
  NSMutableArray *removed = [NSMutableArray array];
  for (LDFileNode *node in volumes) {
    if (![node isKindOfClass:[LDDirectoryNode class]]) {
      continue;
    }
    LDDirectoryNode *volume = (LDDirectoryNode *)node;
    unsigned long long totalBytes = 0;
    unsigned long long freeBytes = 0;
    BOOL known = (showFreeSpace || showUnknown) && usage(volume, &totalBytes, &freeBytes);
    unsigned long long usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0;
    unsigned long long talliedBytes = [self talliedBytesOfVolume:volume];
    LDFileNodeKind kinds[2] = {LDFileNodeKindFreeSpace, LDFileNodeKindUnknown};
    BOOL shown[2] = {showFreeSpace, showUnknown};
    unsigned long long sizes[2] = {freeBytes, talliedBytes > usedBytes ? 0 : usedBytes - talliedBytes};
    BOOL changed = NO;
    int i = 0;
    for (i = 0; i < 2; i++) {
      LDFileNode *item = [self spaceItemOfKind:kinds[i] inVolume:volume];
      if (item && !shown[i]) {
        [removed addObject:item];
        [volume removeChild:item];
        changed = YES;
      } else if (shown[i] && known) {
        // Kept items are updated in place so a selection on them survives.
        if (item) {
          [item setAllocatedSize:sizes[i]];
        } else {
          [volume addChild:[LDFileNode spaceItemWithKind:kinds[i] allocatedSize:sizes[i]]];
        }
        changed = YES;
      }
    }
    if (changed) {
      [volume updateTotalsUpwardSortedByMetric:metric];
    }
  }
  return removed;
}

+ (LDVolumeUsageQuery)diskUsageQuery
{
  return ^BOOL(LDFileNode *volume, unsigned long long *totalBytes, unsigned long long *freeBytes) {
    return [LDVolumes getTotalBytes:totalBytes freeBytes:freeBytes forPathData:[volume pathData]];
  };
}

@end
