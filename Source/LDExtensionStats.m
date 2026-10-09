#import "LDExtensionStats.h"
#import "LDExtensionColor.h"
#import "LDFileNode.h"
#import "LDHardLinks.h"
#import "LDLargestFiles.h"
#import "LDNodeRanking.h"

#include <stdlib.h>

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
  return [self sortedStatsForRootNode:rootNode metric:metric largestFiles:NULL count:0];
}

// Per-extension totals keyed by the extension key's pointer: the scanner
// interns keys, so a scan of millions of files hashes no strings. A key not
// seen by pointer is looked up by value (trees loaded from CSV do not share
// key instances) and added to the entry of an equal key.
typedef struct {
  __unsafe_unretained NSString *key;
  unsigned long long bytes;
  unsigned long long allocatedBytes;
  NSUInteger files;
} LDExtensionTallyEntry;

typedef struct {
  LDExtensionTallyEntry *entries;
  NSUInteger mask;
  NSUInteger count;
  __unsafe_unretained NSMutableDictionary *slotsByKey;
  __unsafe_unretained LDTopNodeCollector *largest;
} LDExtensionTally;

static NSUInteger LDTallySlot(LDExtensionTally *tally, NSString *key)
{
  NSUInteger slot = (NSUInteger)(((uintptr_t)(__bridge void *)key >> 4) * 0x9E3779B97F4A7C15ULL) & tally->mask;
  while (tally->entries[slot].key != nil && tally->entries[slot].key != key) {
    slot = (slot + 1) & tally->mask;
  }
  return slot;
}

static void LDTallyGrow(LDExtensionTally *tally)
{
  LDExtensionTallyEntry *old = tally->entries;
  NSUInteger oldCapacity = tally->mask + 1;
  tally->mask = oldCapacity * 2 - 1;
  tally->entries = calloc(oldCapacity * 2, sizeof(LDExtensionTallyEntry));
  for (NSUInteger index = 0; index < oldCapacity; index++) {
    if (old[index].key != nil) {
      tally->entries[LDTallySlot(tally, old[index].key)] = old[index];
    }
  }
  free(old);
}

static void LDTallyAdd(LDExtensionTally *tally, NSString *key, unsigned long long bytes, unsigned long long allocatedBytes)
{
  LDExtensionTallyEntry *entry = &tally->entries[LDTallySlot(tally, key)];
  if (entry->key == nil) {
    NSString *equalKey = [tally->slotsByKey objectForKey:key];
    if (equalKey) {
      entry = &tally->entries[LDTallySlot(tally, equalKey)];
    } else {
      if ((tally->count + 1) * 2 > tally->mask + 1) {
        LDTallyGrow(tally);
        entry = &tally->entries[LDTallySlot(tally, key)];
      }
      entry->key = key;
      tally->count++;
      [tally->slotsByKey setObject:key forKey:key];
    }
  }
  entry->bytes += bytes;
  entry->allocatedBytes += allocatedBytes;
  entry->files++;
}

static void LDTallyNode(LDExtensionTally *tally, LDFileNode *node)
{
  LDFileNodeKind kind = [node kind];
  if (kind == LDFileNodeKindFile || kind == LDFileNodeKindSymlink) {
    unsigned long long size = [node size];
    LDTallyAdd(tally, [node extensionKey], size, [node allocatedSize]);
    if (tally->largest && [node error] == LDFileNodeErrorNone) {
      [tally->largest offerNode:node size:size];
    }
    return;
  }
  if (kind != LDFileNodeKindDirectory || LDIsHardLinkItem(node)) {
    return;
  }
  for (LDFileNode *child in [node children]) {
    LDTallyNode(tally, child);
  }
}

+ (NSArray *)sortedStatsForRootNode:(id)rootNode
                             metric:(LDSizeMetric)metric
                       largestFiles:(NSArray **)largestFiles
                              count:(NSUInteger)count
{
  LDExtensionTally tally;
  tally.mask = 63;
  tally.count = 0;
  tally.entries = calloc(tally.mask + 1, sizeof(LDExtensionTallyEntry));
  LDTopNodeCollector *largest = (largestFiles && count > 0) ? [[LDTopNodeCollector alloc] initWithLimit:count] : nil;
  NSMutableDictionary *keys = [NSMutableDictionary dictionary];
  tally.largest = largest;
  tally.slotsByKey = keys;
  if (rootNode) {
    LDTallyNode(&tally, rootNode);
  }
  NSMutableArray *stats = [NSMutableArray arrayWithCapacity:tally.count];
  for (NSUInteger index = 0; index <= tally.mask; index++) {
    LDExtensionTallyEntry *entry = &tally.entries[index];
    if (entry->key == nil) {
      continue;
    }
    LDExtensionStats *stat = [[LDExtensionStats alloc] initWithExtensionKey:entry->key];
    stat->_bytes = entry->bytes;
    stat->_allocatedBytes = entry->allocatedBytes;
    stat->_fileCount = entry->files;
    [stats addObject:stat];
  }
  free(tally.entries);
  if (largestFiles) {
    *largestFiles = largest ? [largest sortedNodes] : [NSArray array];
  }
  return [self sortedStats:stats metric:metric];
}

+ (NSArray *)sortedStats:(NSArray *)unsorted metric:(LDSizeMetric)metric
{
  NSArray *sorted = [unsorted sortedArrayUsingFunction:LDCompareStatsByBytes context:(void *)(intptr_t)metric];
  NSUInteger count = [sorted count];
  for (NSUInteger i = 0; i < count; i++) {
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
