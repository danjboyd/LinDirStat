#import <Foundation/Foundation.h>
#import "LDFileNode.h"

// Commands that act on the selection, with WinDirStat's enablement table
// (DirStatDoc.cpp, see docs/windirstat-step-d-reference.md §0).
typedef enum {
  LDCommandOpen = 0,
  LDCommandProperties,
  LDCommandCopyPath,
  LDCommandReveal,
  LDCommandTerminal,
  LDCommandRefreshSelected,
  LDCommandMoveToTrash,
  LDCommandDeletePermanently,
  LDCommandEmptyFolder,
  LDCommandMoveTo,
  LDCommandComputeHash,
  LDCommandCustomCleanup
} LDCommand;

@class LDCustomCleanup;

@interface LDCommandRules : NSObject

// busy is YES while a scan or refresh runs. root is the tree's root. No
// command applies to the "<Hardlinks>" pseudo-items.
+ (BOOL)isCommand:(LDCommand)command
  enabledForNodes:(NSArray *)nodes
         rootNode:(LDFileNode *)root
             busy:(BOOL)busy;

// A custom cleanup applies when it is enabled and every node is of a kind it
// works for (mount points and scan roots, folders, files).
+ (BOOL)isCleanup:(LDCustomCleanup *)cleanup
  enabledForNodes:(NSArray *)nodes
         rootNode:(LDFileNode *)root
             busy:(BOOL)busy;

// WinDirStat's Empty Recycle Bin label: "Empty Trash (N Items, X)…", with
// "X+" when the size is a lower bound (the walk was capped).
+ (NSString *)emptyTrashTitleForItems:(NSUInteger)items
                                bytes:(unsigned long long)bytes
                             complete:(BOOL)complete;

// Nodes with every node that lies below another one in the list removed,
// in their original order. Acting on a folder covers what is inside it.
+ (NSArray *)topmostNodes:(NSArray *)nodes;

// The folders a terminal opens in: each folder itself, a file's parent,
// without repeats.
+ (NSArray *)folderNodesForNodes:(NSArray *)nodes;

// YES for the synthetic "This Computer" root of a multi-volume scan.
+ (BOOL)isComputerNode:(LDFileNode *)node;
// Scan roots and the mount points shown in the tree ("drives").
+ (BOOL)isVolumeNode:(LDFileNode *)node rootNode:(LDFileNode *)root;

@end
