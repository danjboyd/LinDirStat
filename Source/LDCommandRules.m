#import "LDCommandRules.h"
#import "LDFileOperations.h"
#import "LDLocalization.h"
#import "LDSizeFormatter.h"
#import "LDPreferences.h"
#import "LDHardLinks.h"

@implementation LDCommandRules

+ (BOOL)isComputerNode:(LDFileNode *)node
{
  return [node isComputer];
}

+ (BOOL)isVolumeNode:(LDFileNode *)node rootNode:(LDFileNode *)root
{
  if ([self isComputerNode:node]) {
    return NO;
  }
  return node == root || [node isMountPoint] || [self isComputerNode:[node parent]];
}

// The "<Hardlinks>" items are not on disk; no command acts on them.
+ (BOOL)containsPseudoItem:(NSArray *)nodes
{
  for (LDFileNode *node in nodes) {
    if (LDIsHardLinkItem(node)) {
      return YES;
    }
  }
  return NO;
}

+ (BOOL)allNodes:(NSArray *)nodes satisfy:(BOOL (^)(LDFileNode *node))predicate
{
  for (LDFileNode *node in nodes) {
    if (!predicate(node)) {
      return NO;
    }
  }
  return YES;
}

+ (BOOL)anyIsSpaceItem:(NSArray *)nodes
{
  for (LDFileNode *node in nodes) {
    if ([node isSpaceItem]) {
      return YES;
    }
  }
  return NO;
}

+ (BOOL)isCommand:(LDCommand)command
  enabledForNodes:(NSArray *)nodes
         rootNode:(LDFileNode *)root
             busy:(BOOL)busy
{
  // Pseudo-items (<Free Space>, <Unknown>, <Hardlinks>) are none of
  // WinDirStat's command types.
  if ([nodes count] == 0 || [self anyIsSpaceItem:nodes] || [self containsPseudoItem:nodes]) {
    return NO;
  }
  BOOL (^notComputer)(LDFileNode *) = ^BOOL(LDFileNode *node) {
    return ![self isComputerNode:node];
  };
  // Folders and files below the volumes; never a scan root or mount point.
  BOOL (^removable)(LDFileNode *) = ^BOOL(LDFileNode *node) {
    return ![self isComputerNode:node] && ![self isVolumeNode:node rootNode:root];
  };

  switch (command) {
    // These stay available while scanning ("early" in WinDirStat).
    case LDCommandOpen:
    case LDCommandProperties:
    case LDCommandCopyPath:
    case LDCommandReveal:
    case LDCommandTerminal:
      return [self allNodes:nodes satisfy:notComputer];
    case LDCommandComputeHash:
      return [nodes count] == 1 && [(LDFileNode *)[nodes objectAtIndex:0] kind] == LDFileNodeKindFile;
    default:
      break;
  }
  if (busy) {
    return NO;
  }
  switch (command) {
    case LDCommandRefreshSelected:
      return YES;
    case LDCommandMoveToTrash:
    case LDCommandDeletePermanently:
    case LDCommandMoveTo:
    // WinDirStat also takes drives, but excluding a scan root or mount point
    // would empty the scan; the Filtering page still can.
    case LDCommandExcludeItem:
      return [self allNodes:nodes satisfy:removable];
    case LDCommandEmptyFolder:
      return [self allNodes:nodes satisfy:^BOOL(LDFileNode *node) {
        return removable(node) && [node kind] == LDFileNodeKindDirectory;
      }];
    case LDCommandRemoveEmptyFolders:
      return [self allNodes:nodes satisfy:^BOOL(LDFileNode *node) {
        return notComputer(node) && [node kind] == LDFileNodeKindDirectory;
      }];
    default:
      return NO;
  }
}

+ (BOOL)isCleanup:(LDCustomCleanup *)cleanup
  enabledForNodes:(NSArray *)nodes
         rootNode:(LDFileNode *)root
             busy:(BOOL)busy
{
  if (busy || ![cleanup isEnabled] || [[cleanup commandLine] length] == 0 || [nodes count] == 0
      || [self anyIsSpaceItem:nodes] || [self containsPseudoItem:nodes]) {
    return NO;
  }
  return [self allNodes:nodes satisfy:^BOOL(LDFileNode *node) {
    if ([self isComputerNode:node]) {
      return NO;
    }
    if ([self isVolumeNode:node rootNode:root]) {
      return [cleanup worksForMountPoints];
    }
    if ([node kind] == LDFileNodeKindDirectory) {
      return [cleanup worksForDirectories];
    }
    return [cleanup worksForFiles];
  }];
}

+ (void)countFiles:(NSUInteger *)files folders:(NSUInteger *)folders inNodes:(NSArray *)nodes
{
  NSUInteger fileTotal = 0;
  NSUInteger folderTotal = 0;
  for (LDFileNode *node in [self topmostNodes:nodes]) {
    fileTotal += [node fileCount];
    NSUInteger directories = [node directoryCount];
    folderTotal += ([self isComputerNode:node] && directories > 0) ? directories - 1 : directories;
  }
  if (files) {
    *files = fileTotal;
  }
  if (folders) {
    *folders = folderTotal;
  }
}

// A node reached through a symlink, or not a real folder itself: its path
// leads somewhere the tree does not show. Checks the node and its ancestors.
+ (BOOL)isReachedThroughLink:(LDFileNode *)node
{
  for (LDFileNode *cursor = node; cursor && ![self isComputerNode:cursor]; cursor = [cursor parent]) {
    if (![LDFileOperations isRealFolder:[cursor pathData]]) {
      return YES;
    }
  }
  return NO;
}

// Folders whose contents are known: read, and not a mount point left out.
+ (BOOL)isWalkableFolder:(LDFileNode *)node
{
  return [node kind] == LDFileNodeKindDirectory && ![self isComputerNode:node] && [node error] == LDFileNodeErrorNone;
}

+ (NSArray *)emptyFoldersIn:(NSArray *)nodes rootNode:(LDFileNode *)root
{
  NSMutableArray *found = [NSMutableArray array];
  NSMutableArray *stack = [NSMutableArray array];
  for (LDFileNode *node in [self topmostNodes:nodes]) {
    NSArray *starts = [self isComputerNode:node] ? [node children] : @[node];
    for (LDFileNode *start in starts) {
      if ([self isWalkableFolder:start] && ![self isReachedThroughLink:start]) {
        [stack addObject:start];
      }
    }
  }
  // Each folder is recorded before its children, so the reversed list is
  // deepest first.
  while ([stack count] > 0) {
    LDFileNode *node = [stack lastObject];
    [stack removeLastObject];
    if (node != root && ![self isVolumeNode:node rootNode:root] && [node fileCount] == 0) {
      [found addObject:node];
    }
    for (LDFileNode *child in [node children]) {
      if ([self isWalkableFolder:child] && [LDFileOperations isRealFolder:[child pathData]]) {
        [stack addObject:child];
      }
    }
  }
  return [[found reverseObjectEnumerator] allObjects];
}

+ (NSArray *)foldersForDatesIn:(NSArray *)nodes rootNode:(LDFileNode *)root
{
  NSMutableArray *found = [NSMutableArray array];
  NSMutableArray *stack = [NSMutableArray array];
  NSArray *selection = [nodes count] > 0 ? [self topmostNodes:nodes] : (root ? @[root] : @[]);
  for (LDFileNode *node in selection) {
    NSArray *starts = [self isComputerNode:node] ? [node children] : @[node];
    for (LDFileNode *start in starts) {
      if ([self isWalkableFolder:start] && ![self isReachedThroughLink:start]) {
        [stack addObject:start];
      }
    }
  }
  while ([stack count] > 0) {
    LDFileNode *node = [stack lastObject];
    [stack removeLastObject];
    if ([node aggregateModificationTime] > 0) {
      [found addObject:node];
    }
    for (LDFileNode *child in [node children]) {
      if ([self isWalkableFolder:child] && [LDFileOperations isRealFolder:[child pathData]]) {
        [stack addObject:child];
      }
    }
  }
  return found;
}

+ (NSArray *)topmostNodes:(NSArray *)nodes
{
  NSMutableArray *topmost = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    BOOL covered = NO;
    for (LDFileNode *other in nodes) {
      if (other != node && [other isAncestorOf:node]) {
        covered = YES;
        break;
      }
    }
    if (!covered && [topmost indexOfObjectIdenticalTo:node] == NSNotFound) {
      [topmost addObject:node];
    }
  }
  return topmost;
}

+ (NSArray *)folderNodesForNodes:(NSArray *)nodes
{
  NSMutableArray *folders = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    LDFileNode *folder = ([node kind] == LDFileNodeKindDirectory || ![node parent]) ? node : [node parent];
    if ([folders indexOfObjectIdenticalTo:folder] == NSNotFound) {
      [folders addObject:folder];
    }
  }
  return folders;
}

+ (NSString *)emptyTrashTitleForItems:(NSUInteger)items
                                bytes:(unsigned long long)bytes
                             complete:(BOOL)complete
{
  if (items == NSNotFound) {
    return LDLocalized(@"Empty Trash…");
  }
  NSString *size = [LDSizeFormatter stringForBytes:bytes];
  if (!complete) {
    size = [size stringByAppendingString:@"+"];
  }
  NSString *count = items == 1 ? LDLocalized(@"1 Item") : [NSString stringWithFormat:LDLocalized(@"%lu Items"), (unsigned long)items];
  return [NSString stringWithFormat:LDLocalized(@"Empty Trash (%@, %@)…"), count, size];
}

@end
