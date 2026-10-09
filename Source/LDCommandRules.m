#import "LDCommandRules.h"
#import "LDPreferences.h"

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

+ (BOOL)allNodes:(NSArray *)nodes satisfy:(BOOL (^)(LDFileNode *node))predicate
{
  for (LDFileNode *node in nodes) {
    if (!predicate(node)) {
      return NO;
    }
  }
  return YES;
}

+ (BOOL)isCommand:(LDCommand)command
  enabledForNodes:(NSArray *)nodes
         rootNode:(LDFileNode *)root
             busy:(BOOL)busy
{
  if ([nodes count] == 0) {
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
      return [self allNodes:nodes satisfy:removable];
    case LDCommandEmptyFolder:
      return [self allNodes:nodes satisfy:^BOOL(LDFileNode *node) {
        return removable(node) && [node kind] == LDFileNodeKindDirectory;
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
  if (busy || ![cleanup isEnabled] || [[cleanup commandLine] length] == 0 || [nodes count] == 0) {
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

@end
