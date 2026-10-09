#import "LDHardLinks.h"
#import "LDExtensionColor.h"

#include <string.h>

// WinDirStat spreads the Index folders over 20 sets so that no folder gets
// too long (CItem::CreateHardlinksItem).
static const unsigned int LDHardLinkIndexSetCount = 20;

static const char LDHardLinkContainerName[] = "<Hardlinks>";

// The container, the Index sets and the Index folders. They count no files or
// folders and have no time of their own, so the scan's totals stay the same.
@interface LDHardLinkFolderNode : LDDirectoryNode
{
@public
  uint8_t _itemType;
}
@end

// An Index folder: its size is the file's, once, and the treemap draws it as
// a leaf (WinDirStat's TmiIsLeaf), whatever references it holds.
@interface LDHardLinkIndexNode : LDHardLinkFolderNode
{
@public
  LDHardLinkSet *_set;
}
@end

// One link of the file, named by its full path. Its size is shown but not
// added up; the Index folder carries it.
@interface LDHardLinkReferenceNode : LDFileNode
{
@public
  LDFileNode *_link;
  LDHardLinkSet *_set;
}
@end

@implementation LDHardLinkFolderNode
- (NSUInteger)fileCount { return 0; }
- (NSUInteger)directoryCount { return 0; }
- (NSTimeInterval)aggregateModificationTime { return 0; }
@end

@implementation LDHardLinkIndexNode
- (BOOL)isLeaf { return YES; }
- (unsigned long long)aggregateSize { return [_set size]; }
- (unsigned long long)aggregateAllocatedSize { return [_set allocatedSize]; }
@end

@implementation LDHardLinkReferenceNode
- (NSUInteger)fileCount { return 0; }
@end

LDHardLinkItemType LDHardLinkItemTypeOfNode(LDFileNode *node)
{
  if ([node isKindOfClass:[LDHardLinkFolderNode class]]) {
    return (LDHardLinkItemType)((LDHardLinkFolderNode *)node)->_itemType;
  }
  if ([node isKindOfClass:[LDHardLinkReferenceNode class]]) {
    return LDHardLinkItemReference;
  }
  return LDHardLinkItemNone;
}

BOOL LDIsHardLinkItem(LDFileNode *node)
{
  return LDHardLinkItemTypeOfNode(node) != LDHardLinkItemNone;
}

static LDHardLinkFolderNode *LDMakeFolder(Class nodeClass, NSString *name, LDHardLinkItemType type)
{
  const char *bytes = [name UTF8String];
  LDHardLinkFolderNode *folder = [nodeClass nodeWithNameBytes:bytes length:strlen(bytes) arena:nil
                                                         kind:LDFileNodeKindDirectory size:0 allocatedSize:0];
  folder->_itemType = (uint8_t)type;
  return folder;
}

#pragma mark - Sets

@implementation LDHardLinkSet

- (id)initWithDevice:(dev_t)device inode:(unsigned long long)inode
{
  self = [super init];
  if (self) {
    _device = device;
    _inode = inode;
    _members = [[NSMutableArray alloc] init];
  }
  return self;
}

- (dev_t)device { return _device; }
- (unsigned long long)inode { return _inode; }
- (unsigned long long)size { return _size; }
- (unsigned long long)allocatedSize { return _allocatedSize; }
- (NSArray *)members { return [_members copy]; }

- (void)setSize:(unsigned long long)size allocatedSize:(unsigned long long)allocatedSize
{
  _size = size;
  _allocatedSize = allocatedSize;
}

- (NSMutableArray *)mutableMembers { return _members; }

// The link whose bytes the tree counts: the one not marked as a duplicate.
- (BOOL)hasCountedMemberOutside:(LDFileNode *)ignored
{
  for (LDFileNode *member in _members) {
    if (![member isHardLinkDuplicate] && !(ignored && [ignored isAncestorOf:member])) {
      return YES;
    }
  }
  return NO;
}

@end

#pragma mark - Table

@implementation LDHardLinkTable

+ (LDHardLinkTable *)tableForRoot:(LDFileNode *)root
{
  if (![root isKindOfClass:[LDDirectoryNode class]]) {
    return nil;
  }
  id storage = [(LDDirectoryNode *)root ownedStorage];
  if ([storage isKindOfClass:[LDHardLinkTable class]]) {
    return storage;
  }
  if ([storage isKindOfClass:[NSArray class]]) {
    for (id item in storage) {
      if ([item isKindOfClass:[LDHardLinkTable class]]) {
        return item;
      }
    }
  }
  return nil;
}

- (id)init
{
  self = [super init];
  if (self) {
    pthread_mutex_init(&_lock, NULL);
    _setsByIdentity = [[NSMutableDictionary alloc] init];
    _setsByNode = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                        valueOptions:NSPointerFunctionsStrongMemory];
    _retiredItems = [[NSMutableArray alloc] init];
    _showsHardLinks = YES;
  }
  return self;
}

- (void)dealloc
{
  pthread_mutex_destroy(&_lock);
}

- (BOOL)showsHardLinks { return _showsHardLinks; }
- (void)setShowsHardLinks:(BOOL)flag { _showsHardLinks = flag; }
- (BOOL)matchesInodesOnly { return _matchesInodesOnly; }
- (void)setMatchesInodesOnly:(BOOL)flag { _matchesInodesOnly = flag; }

- (BOOL)addLink:(LDFileNode *)node
         device:(dev_t)device
          inode:(unsigned long long)inode
           size:(unsigned long long)size
  allocatedSize:(unsigned long long)allocatedSize
  ignoringLinksUnder:(LDFileNode *)ignored
{
  NSString *key = [NSString stringWithFormat:@"%llu:%llu", _matchesInodesOnly ? 0ULL : (unsigned long long)device, inode];
  pthread_mutex_lock(&_lock);
  LDHardLinkSet *set = [_setsByIdentity objectForKey:key];
  if (!set) {
    set = [[LDHardLinkSet alloc] initWithDevice:device inode:inode];
    [_setsByIdentity setObject:set forKey:key];
  }
  BOOL counted = ![set hasCountedMemberOutside:ignored];
  if (counted) {
    [set setSize:size allocatedSize:allocatedSize];
  } else {
    [node setSize:0 allocatedSize:0];
    [node setError:LDFileNodeErrorHardLinkDuplicate errorNumber:0];
  }
  [[set mutableMembers] addObject:node];
  [_setsByNode setObject:set forKey:node];
  pthread_mutex_unlock(&_lock);
  return counted;
}

- (NSArray *)removeLinksUnder:(LDFileNode *)node
{
  NSMutableArray *promoted = [NSMutableArray array];
  if (!node) {
    return promoted;
  }
  pthread_mutex_lock(&_lock);
  for (NSString *key in [_setsByIdentity allKeys]) {
    LDHardLinkSet *set = [_setsByIdentity objectForKey:key];
    NSMutableArray *members = [set mutableMembers];
    NSIndexSet *gone = [members indexesOfObjectsPassingTest:^BOOL(id member, NSUInteger index, BOOL *stop) {
      (void)index;
      (void)stop;
      return [node isAncestorOf:member];
    }];
    if ([gone count] == 0) {
      continue;
    }
    for (LDFileNode *member in [members objectsAtIndexes:gone]) {
      [_setsByNode removeObjectForKey:member];
    }
    [members removeObjectsAtIndexes:gone];
    if ([members count] == 0) {
      [_setsByIdentity removeObjectForKey:key];
    } else if (![set hasCountedMemberOutside:nil]) {
      LDFileNode *heir = [members objectAtIndex:0];
      [heir setSize:[set size] allocatedSize:[set allocatedSize]];
      [heir setError:LDFileNodeErrorNone errorNumber:0];
      [promoted addObject:heir];
    }
  }
  pthread_mutex_unlock(&_lock);
  return promoted;
}

- (LDHardLinkSet *)setForNode:(LDFileNode *)node
{
  if (!node) {
    return nil;
  }
  pthread_mutex_lock(&_lock);
  LDHardLinkSet *set = [_setsByNode objectForKey:node];
  pthread_mutex_unlock(&_lock);
  return set;
}

- (NSArray *)sets
{
  pthread_mutex_lock(&_lock);
  NSArray *sets = [_setsByIdentity allValues];
  pthread_mutex_unlock(&_lock);
  return [sets sortedArrayUsingComparator:^NSComparisonResult(LDHardLinkSet *left, LDHardLinkSet *right) {
    if ([left inode] != [right inode]) {
      return [left inode] < [right inode] ? NSOrderedAscending : NSOrderedDescending;
    }
    if ([left device] != [right device]) {
      return [left device] < [right device] ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
  }];
}

- (void)retireItems:(NSArray *)items
{
  if ([items count] > 0) {
    [_retiredItems addObject:items];
  }
}

@end

#pragma mark - Tree

static NSComparisonResult LDCompareLinkPaths(id left, id right, void *context)
{
  (void)context;
  NSData *a = [(LDFileNode *)left pathData];
  NSData *b = [(LDFileNode *)right pathData];
  NSUInteger length = MIN([a length], [b length]);
  int order = memcmp([a bytes], [b bytes], length);
  if (order == 0) {
    return [a length] < [b length] ? NSOrderedAscending : ([a length] > [b length] ? NSOrderedDescending : NSOrderedSame);
  }
  return order < 0 ? NSOrderedAscending : NSOrderedDescending;
}

@implementation LDHardLinks

// The root below "This Computer" (or the tree's root) that node is in.
static LDFileNode *LDScanRootOfNode(LDFileNode *node)
{
  LDFileNode *cursor = node;
  while ([cursor parent] && ![[cursor parent] isComputer]) {
    cursor = [cursor parent];
  }
  return cursor;
}

static LDFileNode *LDTopOfNode(LDFileNode *node)
{
  LDFileNode *cursor = node;
  while ([cursor parent]) {
    cursor = [cursor parent];
  }
  return cursor;
}

+ (LDFileNode *)containerForNode:(LDFileNode *)node
{
  LDFileNode *scanRoot = LDScanRootOfNode(node);
  for (LDFileNode *child in [scanRoot children]) {
    if (LDHardLinkItemTypeOfNode(child) == LDHardLinkItemContainer) {
      return child;
    }
  }
  return nil;
}

+ (LDFileNode *)indexNodeForLink:(LDFileNode *)node
{
  if (![node isHardLink]) {
    return nil;
  }
  LDHardLinkSet *set = [[LDHardLinkTable tableForRoot:LDTopOfNode(node)] setForNode:node];
  if (!set) {
    return nil;
  }
  for (LDFileNode *indexSet in [[self containerForNode:node] children]) {
    for (LDFileNode *index in [indexSet children]) {
      if ([self setForItem:index] == set) {
        return index;
      }
    }
  }
  return nil;
}

+ (LDFileNode *)linkForReference:(LDFileNode *)node
{
  return [node isKindOfClass:[LDHardLinkReferenceNode class]] ? ((LDHardLinkReferenceNode *)node)->_link : nil;
}

+ (LDHardLinkSet *)setForItem:(LDFileNode *)node
{
  if ([node isKindOfClass:[LDHardLinkIndexNode class]]) {
    return ((LDHardLinkIndexNode *)node)->_set;
  }
  if ([node isKindOfClass:[LDHardLinkReferenceNode class]]) {
    return ((LDHardLinkReferenceNode *)node)->_set;
  }
  return nil;
}

+ (uint32_t)treemapColor
{
  return LDRGB(200, 150, 100) | LDTreemapColorFlagLighter;
}

// The Index folder of one set, with a reference per link.
+ (LDFileNode *)indexNodeForSet:(LDHardLinkSet *)set links:(NSArray *)links
{
  NSString *name = [NSString stringWithFormat:@"Index 0x%016llX", [set inode]];
  LDHardLinkIndexNode *index = (LDHardLinkIndexNode *)LDMakeFolder([LDHardLinkIndexNode class], name, LDHardLinkItemIndex);
  index->_set = set;
  NSMutableArray *references = [NSMutableArray array];
  for (LDFileNode *link in links) {
    NSData *path = [link pathData];
    LDHardLinkReferenceNode *reference = [LDHardLinkReferenceNode nodeWithNameBytes:[path bytes] length:[path length] arena:nil
                                                                               kind:LDFileNodeKindFile
                                                                               size:[set size]
                                                                      allocatedSize:[set allocatedSize]];
    reference->_link = link;
    reference->_set = set;
    [reference setModificationTime:[link modificationTime]];
    [reference setMode:[link mode]];
    [reference setExtensionKey:[link extensionKey]];
    [references addObject:reference];
  }
  [index publishChildren:references];
  return index;
}

// Fills container with the Index sets for sets (each with its links).
+ (void)fillContainer:(LDDirectoryNode *)container withSets:(NSArray *)sets links:(NSMapTable *)linksBySet
{
  NSMutableArray *buckets = [NSMutableArray array];
  NSMutableArray *bucketChildren = [NSMutableArray array];
  unsigned int bucket = 0;
  for (bucket = 0; bucket < LDHardLinkIndexSetCount; bucket++) {
    [bucketChildren addObject:[NSMutableArray array]];
  }
  for (LDHardLinkSet *set in sets) {
    LDFileNode *index = [self indexNodeForSet:set links:[linksBySet objectForKey:set]];
    [[bucketChildren objectAtIndex:(NSUInteger)([set inode] % LDHardLinkIndexSetCount)] addObject:index];
  }
  for (bucket = 0; bucket < LDHardLinkIndexSetCount; bucket++) {
    NSArray *children = [bucketChildren objectAtIndex:bucket];
    if ([children count] == 0) {
      continue;
    }
    // WinDirStat names the sets 1 to 20 and files inode % 20 under set
    // (inode % 20) + 1.
    NSString *name = [NSString stringWithFormat:@"Index ≡ 0x%02X", bucket + 1];
    LDDirectoryNode *indexSet = LDMakeFolder([LDHardLinkFolderNode class], name, LDHardLinkItemIndexSet);
    [indexSet publishChildren:children];
    [buckets addObject:indexSet];
  }
  [container publishChildren:buckets];
}

+ (void)publishChildren:(NSArray *)children
            ofDirectory:(LDDirectoryNode *)directory
               retiring:(NSMutableArray *)retired
{
  NSArray *old = [directory children];
  if (retired && [old count] > 0) {
    [retired addObject:old];
  }
  [directory publishChildren:children];
}

+ (NSArray *)updateTree:(LDFileNode *)root
                  table:(LDHardLinkTable *)table
                 metric:(LDSizeMetric)metric
               retiring:(NSMutableArray *)retired
{
  NSMutableArray *changed = [NSMutableArray array];
  if (!root || !table) {
    return changed;
  }
  BOOL shows = [table showsHardLinks];
  NSMapTable *setsByScanRoot = [NSMapTable strongToStrongObjectsMapTable];
  NSMapTable *linksBySet = [NSMapTable strongToStrongObjectsMapTable];
  for (LDHardLinkSet *set in [table sets]) {
    NSMutableArray *links = [NSMutableArray array];
    for (LDFileNode *member in [set members]) {
      if ([root isAncestorOf:member]) {
        [links addObject:member];
      }
    }
    BOOL linked = shows && [links count] >= 2;
    for (LDFileNode *link in links) {
      if ([link isHardLink] != linked) {
        [link setHardLink:linked];
        if ([link parent] && [changed indexOfObjectIdenticalTo:[link parent]] == NSNotFound) {
          [changed addObject:[link parent]];
        }
      }
    }
    if (!linked) {
      continue;
    }
    [links sortUsingFunction:LDCompareLinkPaths context:NULL];
    [linksBySet setObject:links forKey:set];
    LDFileNode *scanRoot = LDScanRootOfNode([links objectAtIndex:0]);
    NSMutableArray *rootSets = [setsByScanRoot objectForKey:scanRoot];
    if (!rootSets) {
      rootSets = [NSMutableArray array];
      [setsByScanRoot setObject:rootSets forKey:scanRoot];
    }
    [rootSets addObject:set];
  }

  NSArray *scanRoots = [root isComputer] ? [root children] : @[root];
  for (LDFileNode *scanRoot in scanRoots) {
    if (![scanRoot isKindOfClass:[LDDirectoryNode class]]) {
      continue;
    }
    LDDirectoryNode *directory = (LDDirectoryNode *)scanRoot;
    LDDirectoryNode *container = (LDDirectoryNode *)[self containerForNode:scanRoot];
    NSArray *sets = [setsByScanRoot objectForKey:scanRoot];
    if ([sets count] == 0 && !container) {
      continue;
    }
    if (container) {
      // Views may still hold the old pseudo-items; the table keeps them.
      [table retireItems:[container children]];
    }
    if ([sets count] == 0) {
      NSMutableArray *children = [[directory children] mutableCopy];
      [children removeObjectIdenticalTo:container];
      [table retireItems:@[container]];
      [self publishChildren:children ofDirectory:directory retiring:retired];
    } else {
      if (!container) {
        container = LDMakeFolder([LDHardLinkFolderNode class], @(LDHardLinkContainerName), LDHardLinkItemContainer);
        [table retireItems:@[container]];
        [self publishChildren:[[directory children] arrayByAddingObject:container] ofDirectory:directory retiring:retired];
      }
      [self fillContainer:container withSets:sets links:linksBySet];
      [container recalculateAggregateSize];
      [container sortChildrenByMetric:metric retiring:retired];
    }
    if ([changed indexOfObjectIdenticalTo:directory] == NSNotFound) {
      [changed addObject:directory];
    }
  }
  return changed;
}

@end
