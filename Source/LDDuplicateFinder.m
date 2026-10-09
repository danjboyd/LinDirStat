#import "LDDuplicateFinder.h"
#import "LDHasher.h"
#import "LDNodeRanking.h"

#include <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>

static const unsigned long long LDTierLimits[] = { 4096ULL, 1024ULL * 1024ULL, ULLONG_MAX };
static const NSUInteger LDTierCount = sizeof(LDTierLimits) / sizeof(LDTierLimits[0]);
enum { LDDuplicateDigestLength = 16 };
static const NSUInteger LDExtensionsLabelLimit = 128;
static const NSTimeInterval LDProgressInterval = 0.1;

// What hashing needs of a node, read on the thread that found it. Digests
// are kept per tier so a bucket that grows during a scan is not hashed again.
@interface LDDuplicateCandidate : NSObject
{
@public
  LDFileNode *_node;
  NSData *_pathData;
  unsigned long long _size;
  unsigned long long _allocatedSize;
  uint8_t _digests[3][LDDuplicateDigestLength];
  uint8_t _hashedTiers;
  uint8_t _readableTiers;
}
@end

@implementation LDDuplicateCandidate
@end

static LDDuplicateCandidate *LDMakeCandidate(LDFileNode *node, NSData *pathData)
{
  LDDuplicateCandidate *candidate = [[LDDuplicateCandidate alloc] init];
  candidate->_node = node;
  candidate->_pathData = pathData;
  candidate->_size = [node size];
  candidate->_allocatedSize = [node allocatedSize];
  return candidate;
}

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

static BOOL LDIsCancelled(const int *cancelled)
{
  return cancelled && __atomic_load_n(cancelled, __ATOMIC_RELAXED) != 0;
}

// The candidate's digest for a tier, hashed once and then remembered. nil if
// the file cannot be read, or once cancelled (then nothing is remembered).
static NSData *LDCandidateDigest(LDDuplicateCandidate *candidate, NSUInteger tier, const int *cancelled)
{
  uint8_t bit = (uint8_t)(1u << tier);
  if (!(candidate->_hashedTiers & bit)) {
    NSData *digest = [LDHasher duplicateDigestForFileAtPath:candidate->_pathData
                                                  byteLimit:LDTierLimits[tier]
                                                  cancelled:cancelled
                                                      error:NULL];
    if (LDIsCancelled(cancelled)) {
      return nil;
    }
    candidate->_hashedTiers |= bit;
    if ([digest length] == LDDuplicateDigestLength) {
      memcpy(candidate->_digests[tier], [digest bytes], LDDuplicateDigestLength);
      candidate->_readableTiers |= bit;
    }
  }
  if (!(candidate->_readableTiers & bit)) {
    return nil;
  }
  return [NSData dataWithBytes:candidate->_digests[tier] length:LDDuplicateDigestLength];
}

// Splits each set by its files' digests at tier, keeping sets of two or
// more. Unreadable files are dropped. nil once cancelled.
static NSArray *LDSplitSets(NSArray *sets, NSUInteger tier, const int *cancelled)
{
  NSMutableArray *result = [NSMutableArray array];
  for (NSArray *set in sets) {
    NSMutableDictionary *byDigest = [NSMutableDictionary dictionary];
    for (LDDuplicateCandidate *candidate in set) {
      NSData *digest = LDCandidateDigest(candidate, tier, cancelled);
      if (LDIsCancelled(cancelled)) {
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
    for (NSArray *matches in [byDigest objectEnumerator]) {
      if ([matches count] >= 2) {
        [result addObject:matches];
      }
    }
  }
  return result;
}

static LDDuplicateGroup *LDGroupWithCandidates(NSArray *candidates, NSUInteger tier)
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
  NSData *digest = [NSData dataWithBytes:first->_digests[tier] length:LDDuplicateDigestLength];
  return [[LDDuplicateGroup alloc] initWithHashString:[LDHasher hexStringForData:digest]
                                          logicalSize:first->_size
                                                nodes:nodes
                                    totalPhysicalSize:physical];
}

// WinDirStat's tiers (FileDupeControl.cpp): a bucket of equal-sized files is
// split by the digest of each tier up to the one that covers the whole file.
// Returns the bucket's groups, or nil once cancelled.
static NSArray *LDGroupsForBucket(NSArray *bucket, const int *cancelled)
{
  unsigned long long size = ((LDDuplicateCandidate *)[bucket objectAtIndex:0])->_size;
  NSArray *sets = [NSArray arrayWithObject:bucket];
  NSUInteger tier = 0;
  for (; tier < LDTierCount; tier++) {
    sets = LDSplitSets(sets, tier, cancelled);
    if (!sets) {
      return nil;
    }
    if ([sets count] == 0 || size <= LDTierLimits[tier]) {
      break;
    }
  }
  NSMutableArray *groups = [NSMutableArray arrayWithCapacity:[sets count]];
  for (NSArray *set in sets) {
    [groups addObject:LDGroupWithCandidates(set, tier)];
  }
  return groups;
}

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
    LDFileNode *node = files[index].node;
    LDDuplicateCandidate *candidate = LDMakeCandidate(node, [node pathData]);
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

// Groups for one bucket of equal-sized files, or nil once cancelled.
- (NSArray *)groupsForBucket:(NSArray *)bucket
{
  return LDGroupsForBucket(bucket, &_cancelled);
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

// One size seen during a scan: the first file while it is alone, then the
// index of its bucket.
struct LDSizeSlot {
  unsigned long long size;
  void *first;
  NSInteger bucket;
};

static const NSTimeInterval LDCollectorUpdateInterval = 0.5;

@interface LDDuplicateBucket : NSObject
{
@public
  NSMutableArray *_members;
  NSArray *_groups;
  BOOL _dirty;
}
@end

@implementation LDDuplicateBucket
@end

typedef struct {
  __unsafe_unretained LDFileNode *node;
  NSInteger bucket;
} LDBucketAddition;

@implementation LDDuplicateCollector

- (id)init
{
  self = [super init];
  if (self) {
    pthread_mutex_init(&_lock, NULL);
    pthread_cond_init(&_finishedCondition, NULL);
    _buckets = [[NSMutableArray alloc] init];
    _dirtyBuckets = [[NSMutableArray alloc] init];
    [self allocateSlots:1024];
  }
  return self;
}

- (void)dealloc
{
  free(_slots);
  pthread_cond_destroy(&_finishedCondition);
  pthread_mutex_destroy(&_lock);
}

- (void)allocateSlots:(NSUInteger)capacity
{
  _slots = malloc(capacity * sizeof(struct LDSizeSlot));
  for (NSUInteger index = 0; index < capacity; index++) {
    _slots[index].first = NULL;
    _slots[index].bucket = -1;
  }
  _slotMask = capacity - 1;
}

static BOOL LDSlotIsEmpty(const struct LDSizeSlot *slot)
{
  return slot->first == NULL && slot->bucket < 0;
}

- (struct LDSizeSlot *)slotForSize:(unsigned long long)size
{
  NSUInteger index = (NSUInteger)((size * 0x9E3779B97F4A7C15ULL) >> 20) & _slotMask;
  while (!LDSlotIsEmpty(&_slots[index]) && _slots[index].size != size) {
    index = (index + 1) & _slotMask;
  }
  return &_slots[index];
}

// Keeps the table at most half full.
- (void)growSlotsIfNeeded
{
  if ((_slotsUsed + 1) * 2 <= _slotMask + 1) {
    return;
  }
  struct LDSizeSlot *old = _slots;
  NSUInteger oldCapacity = _slotMask + 1;
  [self allocateSlots:oldCapacity * 2];
  for (NSUInteger index = 0; index < oldCapacity; index++) {
    if (!LDSlotIsEmpty(&old[index])) {
      *[self slotForSize:old[index].size] = old[index];
    }
  }
  free(old);
}

- (BOOL)isCancelled
{
  return __atomic_load_n(&_cancelled, __ATOMIC_RELAXED) != 0;
}

- (BOOL)isFinished
{
  pthread_mutex_lock(&_lock);
  BOOL finished = _finished;
  pthread_mutex_unlock(&_lock);
  return finished;
}

#pragma mark - Adding (scanner workers)

- (void)addNodes:(NSArray *)nodes
{
  if ([self isCancelled]) {
    return;
  }
  // Under the lock, sizes are counted and the files that join a bucket are
  // noted; their paths are built outside it.
  LDBucketAddition *additions = NULL;
  NSUInteger additionCount = 0;
  pthread_mutex_lock(&_lock);
  if (_finished || _addingFinished) {
    pthread_mutex_unlock(&_lock);
    return;
  }
  for (LDFileNode *node in nodes) {
    if (![LDDuplicateFinder isCandidate:node]) {
      continue;
    }
    [self growSlotsIfNeeded];
    struct LDSizeSlot *slot = [self slotForSize:[node size]];
    if (LDSlotIsEmpty(slot)) {
      slot->size = [node size];
      slot->first = (__bridge void *)node;
      _slotsUsed++;
      continue;
    }
    if (!additions) {
      // A file can bring the first file of its size along.
      additions = malloc(2 * [nodes count] * sizeof(LDBucketAddition));
    }
    if (slot->bucket < 0) {
      slot->bucket = (NSInteger)[_buckets count];
      LDDuplicateBucket *bucket = [[LDDuplicateBucket alloc] init];
      bucket->_members = [[NSMutableArray alloc] initWithCapacity:2];
      [_buckets addObject:bucket];
      additions[additionCount].node = (__bridge LDFileNode *)slot->first;
      additions[additionCount++].bucket = slot->bucket;
      slot->first = NULL;
    }
    additions[additionCount].node = node;
    additions[additionCount++].bucket = slot->bucket;
  }
  pthread_mutex_unlock(&_lock);
  if (additionCount == 0) {
    free(additions);
    return;
  }

  NSMutableArray *candidates = [NSMutableArray arrayWithCapacity:additionCount];
  for (NSUInteger index = 0; index < additionCount; index++) {
    [candidates addObject:LDMakeCandidate(additions[index].node, [additions[index].node pathData])];
  }

  BOOL startDraining = NO;
  pthread_mutex_lock(&_lock);
  if (!_finished) {
    for (NSUInteger index = 0; index < additionCount; index++) {
      LDDuplicateBucket *bucket = [_buckets objectAtIndex:(NSUInteger)additions[index].bucket];
      [bucket->_members addObject:[candidates objectAtIndex:index]];
      if (!bucket->_dirty) {
        bucket->_dirty = YES;
        [_dirtyBuckets addObject:bucket];
      }
    }
    startDraining = !_draining;
    _draining = YES;
  }
  pthread_mutex_unlock(&_lock);
  free(additions);
  if (startDraining) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
      [self drain];
    });
  }
}

- (void)finishAdding
{
  pthread_mutex_lock(&_lock);
  _addingFinished = YES;
  // Sizes are only needed while files are added; the first-file pointers
  // must not be used once the scan is over.
  free(_slots);
  _slots = NULL;
  _slotMask = 0;
  BOOL finished = [self finishIfIdleLocked];
  pthread_mutex_unlock(&_lock);
  if (finished) {
    [self didFinish];
  }
}

- (void)cancel
{
  __atomic_store_n(&_cancelled, 1, __ATOMIC_RELAXED);
  pthread_mutex_lock(&_lock);
  BOOL finished = [self finishIfIdleLocked];
  pthread_mutex_unlock(&_lock);
  if (finished) {
    [self didFinish];
  }
}

#pragma mark - Hashing (low-priority queue)

// Hashes dirty buckets until none are left. Only one drain runs at a time,
// so candidates' digest caches have a single writer.
- (void)drain
{
  while (YES) {
    pthread_mutex_lock(&_lock);
    NSArray *batch = _dirtyBuckets;
    if ([batch count] == 0 || [self isCancelled]) {
      _draining = NO;
      BOOL finished = [self finishIfIdleLocked];
      pthread_mutex_unlock(&_lock);
      if (finished) {
        [self didFinish];
      }
      return;
    }
    _dirtyBuckets = [[NSMutableArray alloc] init];
    pthread_mutex_unlock(&_lock);

    for (LDDuplicateBucket *bucket in batch) {
      @autoreleasepool {
        pthread_mutex_lock(&_lock);
        bucket->_dirty = NO;
        NSArray *members = [bucket->_members copy];
        pthread_mutex_unlock(&_lock);
        NSArray *groups = LDGroupsForBucket(members, &_cancelled);
        if (!groups) {
          break;
        }
        pthread_mutex_lock(&_lock);
        bucket->_groups = groups;
        pthread_mutex_unlock(&_lock);
      }
      [self scheduleUpdate];
    }
  }
}

// YES the first time the collector is done: nothing more will be added (or
// it was cancelled) and no drain is running.
- (BOOL)finishIfIdleLocked
{
  if (_finished || _draining || !(_addingFinished || [self isCancelled])) {
    return NO;
  }
  _finished = YES;
  return YES;
}

- (NSArray *)unsortedGroupsLocked
{
  NSMutableArray *groups = [NSMutableArray array];
  for (LDDuplicateBucket *bucket in _buckets) {
    if (bucket->_groups) {
      [groups addObjectsFromArray:bucket->_groups];
    }
  }
  return groups;
}

// Keeps only the groups; the candidates and their paths are released.
- (void)didFinish
{
  pthread_mutex_lock(&_lock);
  NSArray *groups = [self unsortedGroupsLocked];
  pthread_mutex_unlock(&_lock);
  NSArray *sorted = [LDDuplicateFinder sortedGroups:groups];
  pthread_mutex_lock(&_lock);
  _finalGroups = sorted;
  _buckets = nil;
  _dirtyBuckets = nil;
  free(_slots);
  _slots = NULL;
  pthread_cond_broadcast(&_finishedCondition);
  pthread_mutex_unlock(&_lock);
  [self scheduleUpdate];
}

- (void)waitUntilFinished
{
  pthread_mutex_lock(&_lock);
  while (!_finalGroups) {
    pthread_cond_wait(&_finishedCondition, &_lock);
  }
  pthread_mutex_unlock(&_lock);
}

- (NSArray *)groups
{
  pthread_mutex_lock(&_lock);
  NSArray *final = _finalGroups;
  NSArray *groups = final ? nil : [self unsortedGroupsLocked];
  pthread_mutex_unlock(&_lock);
  return final ?: [LDDuplicateFinder sortedGroups:groups];
}

#pragma mark - Updates (main queue)

- (void)setUpdateHandler:(void (^)(NSArray *groups, BOOL finished))handler
{
  pthread_mutex_lock(&_lock);
  _updateHandler = [handler copy];
  pthread_mutex_unlock(&_lock);
  [self scheduleUpdate];
}

- (void)scheduleUpdate
{
  pthread_mutex_lock(&_lock);
  BOOL schedule = _updateHandler && !_notificationScheduled;
  _notificationScheduled = _notificationScheduled || schedule;
  NSTimeInterval delay = _finalGroups ? 0.0 : LDCollectorUpdateInterval;
  pthread_mutex_unlock(&_lock);
  if (!schedule) {
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self deliverUpdate];
  });
}

- (void)deliverUpdate
{
  pthread_mutex_lock(&_lock);
  _notificationScheduled = NO;
  void (^handler)(NSArray *, BOOL) = _updateHandler;
  BOOL finished = _finalGroups != nil;
  if (finished) {
    // The handler usually references whoever holds the collector.
    _updateHandler = nil;
  }
  pthread_mutex_unlock(&_lock);
  if (handler) {
    handler([self groups], finished);
  }
}

@end
