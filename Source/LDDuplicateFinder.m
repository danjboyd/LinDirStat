#import "LDDuplicateFinder.h"
#import "LDHasher.h"
#import "LDNodeRanking.h"

#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>

static const unsigned long long LDTierLimits[] = { 4096ULL, 1024ULL * 1024ULL, ULLONG_MAX };
static const NSUInteger LDTierCount = sizeof(LDTierLimits) / sizeof(LDTierLimits[0]);
static const NSUInteger LDExtensionsLabelLimit = 128;
static const NSTimeInterval LDProgressInterval = 0.1;

// What the background queue needs of a node, read on the calling thread.
@interface LDDuplicateCandidate : NSObject
{
@public
  LDFileNode *_node;
  NSData *_pathData;
  unsigned long long _size;
  unsigned long long _allocatedSize;
}
@end

@implementation LDDuplicateCandidate
@end

static NSComparisonResult LDComparePathData(NSData *left, NSData *right)
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

// Open-addressing table from logical size to file count and bucket index,
// so millions of files can be bucketed without an object per file.
typedef struct {
  unsigned long long *sizes;
  NSUInteger *counts;
  NSInteger *bucketIndexes;
  NSUInteger mask;
} LDSizeTable;

static void LDSizeTableInit(LDSizeTable *table, NSUInteger entries)
{
  NSUInteger capacity = 16;
  while (capacity < entries * 2) {
    capacity *= 2;
  }
  table->sizes = calloc(capacity, sizeof(unsigned long long));
  table->counts = calloc(capacity, sizeof(NSUInteger));
  table->bucketIndexes = malloc(capacity * sizeof(NSInteger));
  for (NSUInteger index = 0; index < capacity; index++) {
    table->bucketIndexes[index] = -1;
  }
  table->mask = capacity - 1;
}

static void LDSizeTableFree(LDSizeTable *table)
{
  free(table->sizes);
  free(table->counts);
  free(table->bucketIndexes);
}

static NSUInteger LDSizeTableSlot(LDSizeTable *table, unsigned long long size)
{
  NSUInteger slot = (NSUInteger)((size * 0x9E3779B97F4A7C15ULL) >> 20) & table->mask;
  while (table->counts[slot] != 0 && table->sizes[slot] != size) {
    slot = (slot + 1) & table->mask;
  }
  return slot;
}

typedef struct {
  __unsafe_unretained LDFileNode *node;
  unsigned long long size;
} LDSizedNode;

@implementation LDDuplicateGroup

- (id)initWithHashString:(NSString *)hashString
             logicalSize:(unsigned long long)logicalSize
                   nodes:(NSArray *)nodes
       totalPhysicalSize:(unsigned long long)totalPhysicalSize
{
  self = [super init];
  if (self) {
    _hashString = [hashString copy];
    _logicalSize = logicalSize;
    _nodes = [nodes copy];
    _totalPhysicalSize = totalPhysicalSize;
  }
  return self;
}

- (NSString *)hashString { return _hashString; }
- (unsigned long long)logicalSize { return _logicalSize; }
- (NSArray *)nodes { return _nodes; }
- (NSUInteger)count { return [_nodes count]; }
- (unsigned long long)totalLogicalSize { return _logicalSize * [_nodes count]; }
- (unsigned long long)totalPhysicalSize { return _totalPhysicalSize; }

- (NSString *)extensionsLabel
{
  if (_extensionsLabel) {
    return _extensionsLabel;
  }
  NSMutableArray *extensions = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  for (LDFileNode *node in _nodes) {
    NSString *key = [node extensionKey];
    if ([seen containsObject:key]) {
      continue;
    }
    [seen addObject:key];
    [extensions addObject:[key isEqualToString:@"<none>"] ? @".???" : [@"." stringByAppendingString:key]];
  }
  NSString *joined = [extensions componentsJoinedByString:@", "];
  if ([joined length] > LDExtensionsLabelLimit) {
    joined = [[joined substringToIndex:LDExtensionsLabelLimit] stringByAppendingString:@"…"];
  }
  _extensionsLabel = [NSString stringWithFormat:@"(%@)", joined];
  return _extensionsLabel;
}

@end

@implementation LDDuplicateFinder

- (id)initWithRootNode:(LDFileNode *)root
{
  self = [super init];
  if (self) {
    _root = root;
  }
  return self;
}

- (void)cancel
{
  __atomic_store_n(&_cancelled, 1, __ATOMIC_RELAXED);
}

- (BOOL)isCancelled
{
  return __atomic_load_n(&_cancelled, __ATOMIC_RELAXED) != 0;
}

+ (BOOL)isCandidate:(LDFileNode *)node
{
  return [node kind] == LDFileNodeKindFile && [node error] == LDFileNodeErrorNone;
}

// Buckets of two or more candidates with equal logical size. Runs on the
// calling thread: it is the only place nodes are read.
- (NSArray *)snapshotBuckets
{
  __block LDSizedNode *files = NULL;
  __block NSUInteger fileCount = 0;
  __block NSUInteger fileCapacity = 0;
  LDVisitNodes(_root, ^(LDFileNode *node) {
    if (![LDDuplicateFinder isCandidate:node]) {
      return;
    }
    if (fileCount == fileCapacity) {
      fileCapacity = fileCapacity ? fileCapacity * 2 : 1024;
      files = realloc(files, fileCapacity * sizeof(LDSizedNode));
    }
    files[fileCount].node = node;
    files[fileCount].size = [node size];
    fileCount++;
  });

  LDSizeTable table;
  LDSizeTableInit(&table, fileCount);
  for (NSUInteger index = 0; index < fileCount; index++) {
    NSUInteger slot = LDSizeTableSlot(&table, files[index].size);
    table.sizes[slot] = files[index].size;
    table.counts[slot]++;
  }

  NSMutableArray *buckets = [NSMutableArray array];
  for (NSUInteger index = 0; index < fileCount; index++) {
    NSUInteger slot = LDSizeTableSlot(&table, files[index].size);
    if (table.counts[slot] < 2) {
      continue;
    }
    if (table.bucketIndexes[slot] < 0) {
      table.bucketIndexes[slot] = (NSInteger)[buckets count];
      [buckets addObject:[NSMutableArray arrayWithCapacity:table.counts[slot]]];
    }
    LDDuplicateCandidate *candidate = [[LDDuplicateCandidate alloc] init];
    LDFileNode *node = files[index].node;
    candidate->_node = node;
    candidate->_pathData = [node pathData];
    candidate->_size = files[index].size;
    candidate->_allocatedSize = [node allocatedSize];
    [[buckets objectAtIndex:(NSUInteger)table.bucketIndexes[slot]] addObject:candidate];
  }
  LDSizeTableFree(&table);
  free(files);
  return buckets;
}

+ (NSUInteger)candidateCountInBuckets:(NSArray *)buckets
{
  NSUInteger count = 0;
  for (NSArray *bucket in buckets) {
    count += [bucket count];
  }
  return count;
}

// Splits each set by the digest of its files' first limit bytes, keeping
// sets of two or more. Unreadable files are dropped. nil once cancelled.
- (NSArray *)splitSets:(NSArray *)sets byteLimit:(unsigned long long)limit digests:(NSMutableDictionary *)digests
{
  NSMutableArray *result = [NSMutableArray array];
  for (NSArray *set in sets) {
    NSMutableDictionary *byDigest = [NSMutableDictionary dictionary];
    for (LDDuplicateCandidate *candidate in set) {
      NSData *digest = [LDHasher duplicateDigestForFileAtPath:candidate->_pathData
                                                    byteLimit:limit
                                                    cancelled:&_cancelled
                                                        error:NULL];
      if ([self isCancelled]) {
        return nil;
      }
      if (!digest) {
        continue;
      }
      NSMutableArray *matches = [byDigest objectForKey:digest];
      if (!matches) {
        matches = [NSMutableArray array];
        [byDigest setObject:matches forKey:digest];
      }
      [matches addObject:candidate];
    }
    for (NSData *digest in byDigest) {
      NSArray *matches = [byDigest objectForKey:digest];
      if ([matches count] >= 2) {
        [result addObject:matches];
        [digests setObject:digest forKey:[NSValue valueWithNonretainedObject:matches]];
      }
    }
  }
  return result;
}

+ (LDDuplicateGroup *)groupWithCandidates:(NSArray *)candidates digest:(NSData *)digest
{
  NSArray *sorted = [candidates sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
    return LDComparePathData(((LDDuplicateCandidate *)left)->_pathData, ((LDDuplicateCandidate *)right)->_pathData);
  }];
  NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:[sorted count]];
  unsigned long long physical = 0;
  for (LDDuplicateCandidate *candidate in sorted) {
    [nodes addObject:candidate->_node];
    physical += candidate->_allocatedSize;
  }
  LDDuplicateCandidate *first = [sorted objectAtIndex:0];
  return [[LDDuplicateGroup alloc] initWithHashString:[LDHasher hexStringForData:digest]
                                          logicalSize:first->_size
                                                nodes:nodes
                                    totalPhysicalSize:physical];
}

// Groups for one bucket of equal-sized files, or nil once cancelled.
- (NSArray *)groupsForBucket:(NSArray *)bucket
{
  unsigned long long size = ((LDDuplicateCandidate *)[bucket objectAtIndex:0])->_size;
  NSArray *sets = [NSArray arrayWithObject:bucket];
  NSMutableDictionary *digests = nil;
  for (NSUInteger tier = 0; tier < LDTierCount && [sets count] > 0; tier++) {
    digests = [NSMutableDictionary dictionary];
    sets = [self splitSets:sets byteLimit:LDTierLimits[tier] digests:digests];
    if (!sets) {
      return nil;
    }
    if (size <= LDTierLimits[tier]) {
      break;
    }
  }
  NSMutableArray *groups = [NSMutableArray arrayWithCapacity:[sets count]];
  for (NSArray *set in sets) {
    NSData *digest = [digests objectForKey:[NSValue valueWithNonretainedObject:set]];
    [groups addObject:[LDDuplicateFinder groupWithCandidates:set digest:digest]];
  }
  return groups;
}

+ (NSArray *)sortedGroups:(NSArray *)groups
{
  return [groups sortedArrayUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
    LDDuplicateGroup *left = leftObject;
    LDDuplicateGroup *right = rightObject;
    if ([left totalPhysicalSize] != [right totalPhysicalSize]) {
      return [left totalPhysicalSize] > [right totalPhysicalSize] ? NSOrderedAscending : NSOrderedDescending;
    }
    return [[left hashString] compare:[right hashString]];
  }];
}

// report receives the running count of candidates with a final verdict.
- (NSArray *)groupsForBuckets:(NSArray *)buckets report:(void (^)(NSUInteger hashedFiles))report
{
  NSMutableArray *groups = [NSMutableArray array];
  NSUInteger hashed = 0;
  for (NSArray *bucket in buckets) {
    NSArray *bucketGroups = [self groupsForBucket:bucket];
    if (!bucketGroups) {
      return nil;
    }
    [groups addObjectsFromArray:bucketGroups];
    hashed += [bucket count];
    if (report) {
      report(hashed);
    }
  }
  return [LDDuplicateFinder sortedGroups:groups];
}

- (NSArray *)findGroups
{
  return [self groupsForBuckets:[self snapshotBuckets] report:nil];
}

- (void)startWithProgress:(void (^)(NSUInteger hashedFiles, NSUInteger candidateFiles))progress
               completion:(void (^)(NSArray *groups))completion
{
  NSArray *buckets = [self snapshotBuckets];
  NSUInteger candidates = [LDDuplicateFinder candidateCountInBuckets:buckets];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    __block NSTimeInterval lastReport = 0;
    NSArray *groups = [self groupsForBuckets:buckets report:^(NSUInteger hashedFiles) {
      NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
      if (!progress || now - lastReport < LDProgressInterval) {
        return;
      }
      lastReport = now;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (![self isCancelled]) {
          progress(hashedFiles, candidates);
        }
      });
    }];
    if (!groups) {
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self isCancelled]) {
        return;
      }
      if (progress) {
        progress(candidates, candidates);
      }
      if (completion) {
        completion(groups);
      }
    });
  });
}

+ (BOOL)node:(LDFileNode *)node isUnderAnyOf:(NSArray *)removed
{
  for (LDFileNode *candidate in removed) {
    if ([candidate isAncestorOf:node]) {
      return YES;
    }
  }
  return NO;
}

+ (NSArray *)groups:(NSArray *)groups removingNodesUnder:(NSArray *)nodes
{
  NSMutableArray *result = [NSMutableArray arrayWithCapacity:[groups count]];
  for (LDDuplicateGroup *group in groups) {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:[group count]];
    unsigned long long physical = 0;
    for (LDFileNode *node in [group nodes]) {
      if (![self node:node isUnderAnyOf:nodes]) {
        [kept addObject:node];
        physical += [node allocatedSize];
      }
    }
    if ([kept count] == [group count]) {
      [result addObject:group];
    } else if ([kept count] >= 2) {
      [result addObject:[[LDDuplicateGroup alloc] initWithHashString:[group hashString]
                                                         logicalSize:[group logicalSize]
                                                               nodes:kept
                                                   totalPhysicalSize:physical]];
    }
  }
  return [self sortedGroups:result];
}

@end
