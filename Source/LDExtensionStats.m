#import "LDExtensionStats.h"
#import "LDExtensionColor.h"
#import "LDFileNode.h"
#import "LDHardLinks.h"

@implementation LDExtensionStats

+ (NSString *)extensionKeyForFilename:(NSString *)filename
{
  NSString *name = filename;
  NSRange slash = [name rangeOfString:@"/" options:NSBackwardsSearch];
  if (slash.location != NSNotFound) {
    name = [name substringFromIndex:slash.location + 1];
  }
  // A leading dot marks a hidden file, not an extension (".profile").
  NSUInteger length = [name length];
  NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
  if (dot.location == NSNotFound || dot.location == 0 || dot.location + 1 >= length) {
    return @"<none>";
  }
  return [[name substringFromIndex:dot.location + 1] lowercaseString];
}

+ (void)collectNode:(LDFileNode *)node intoStats:(NSMutableDictionary *)stats
{
  LDFileNodeKind kind = [node kind];
  if (kind == LDFileNodeKindFile || kind == LDFileNodeKindSymlink) {
    NSString *key = [node extensionKey];
    LDExtensionStats *entry = [stats objectForKey:key];
    if (!entry) {
      entry = [[LDExtensionStats alloc] initWithExtensionKey:key];
      [stats setObject:entry forKey:key];
    }
    [entry addBytes:[node size] allocatedBytes:[node allocatedSize]];
    return;
  }
  // The "<Hardlinks>" pseudo-folders repeat files counted where they are.
  if (LDIsHardLinkItem(node)) {
    return;
  }

  NSArray *children = [node children];
  NSUInteger count = [children count];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    [self collectNode:[children objectAtIndex:i] intoStats:stats];
  }
}

static NSComparisonResult LDCompareStatsByBytes(id left, id right, void *context)
{
  LDSizeMetric metric = (LDSizeMetric)(intptr_t)context;
  unsigned long long leftBytes = [(LDExtensionStats *)left bytesForMetric:metric];
  unsigned long long rightBytes = [(LDExtensionStats *)right bytesForMetric:metric];
  if (leftBytes > rightBytes) {
    return NSOrderedAscending;
  }
  if (leftBytes < rightBytes) {
    return NSOrderedDescending;
  }
  return [[left extensionKey] compare:[right extensionKey]];
}

+ (NSArray *)sortedStatsForRootNode:(id)rootNode
{
  return [self sortedStatsForRootNode:rootNode metric:LDSizeMetricLogical];
}

+ (NSArray *)sortedStatsForRootNode:(id)rootNode metric:(LDSizeMetric)metric
{
  NSMutableDictionary *stats = [NSMutableDictionary dictionary];
  if (rootNode) {
    [self collectNode:rootNode intoStats:stats];
  }
  NSArray *sorted = [[stats allValues] sortedArrayUsingFunction:LDCompareStatsByBytes
                                                        context:(void *)(intptr_t)metric];
  NSUInteger count = [sorted count];
  NSUInteger i = 0;
  for (i = 0; i < count; i++) {
    [[sorted objectAtIndex:i] setColorIndex:[LDExtensionColor paletteIndexForRank:i]];
  }
  return sorted;
}

+ (NSDictionary *)colorIndexMapForSortedStats:(NSArray *)stats
{
  NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:[stats count]];
  NSEnumerator *enumerator = [stats objectEnumerator];
  LDExtensionStats *entry = nil;
  while ((entry = [enumerator nextObject])) {
    [map setObject:[NSNumber numberWithUnsignedInteger:[entry colorIndex]] forKey:[entry extensionKey]];
  }
  return map;
}

- (id)initWithExtensionKey:(NSString *)extensionKey
{
  self = [super init];
  if (self) {
    _extensionKey = [extensionKey copy];
    if ([extensionKey isEqualToString:@"<none>"]) {
      _displayName = [@"[no extension]" copy];
    } else {
      _displayName = [[@"." stringByAppendingString:extensionKey] copy];
    }
  }
  return self;
}

- (NSString *)extensionKey { return _extensionKey; }
- (NSString *)displayName { return _displayName; }
- (unsigned long long)bytes { return _bytes; }
- (unsigned long long)allocatedBytes { return _allocatedBytes; }
- (NSUInteger)fileCount { return _fileCount; }
- (NSUInteger)colorIndex { return _colorIndex; }
- (void)setColorIndex:(NSUInteger)colorIndex { _colorIndex = colorIndex; }

- (unsigned long long)bytesForMetric:(LDSizeMetric)metric
{
  return metric == LDSizeMetricLogical ? _bytes : _allocatedBytes;
}

- (double)percentageOfTotal:(unsigned long long)totalBytes
{
  return [self percentageOfTotal:totalBytes metric:LDSizeMetricLogical];
}

- (double)percentageOfTotal:(unsigned long long)totalBytes metric:(LDSizeMetric)metric
{
  if (totalBytes == 0) {
    return 0.0;
  }
  return ((double)[self bytesForMetric:metric] / (double)totalBytes) * 100.0;
}

- (void)addBytes:(unsigned long long)bytes
{
  [self addBytes:bytes allocatedBytes:bytes];
}

- (void)addBytes:(unsigned long long)bytes allocatedBytes:(unsigned long long)allocatedBytes
{
  _bytes += bytes;
  _allocatedBytes += allocatedBytes;
  _fileCount += 1;
}


@end
