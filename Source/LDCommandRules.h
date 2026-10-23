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
  LDCommandCustomCleanup,
  // Add to Exclusion Filter (WinDirStat 2.5.8): folders and files below the
  // scan roots, not while busy.
  LDCommandExcludeItem,
  // WinDirStat 2.7's Remove Empty Folders: folders, scan roots included
  // (their empty folders go, never the root), not while busy.
  LDCommandRemoveEmptyFolders
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

// WinDirStat 2.6's status text for several selected items (9e134e2d): the
// files and folders they hold, each counting itself. A node below another
// selected one is counted once; "This Computer" is not a folder.
+ (void)countFiles:(NSUInteger *)files folders:(NSUInteger *)folders inNodes:(NSArray *)nodes;

// Remove Empty Folders (WinDirStat 2.7, 262a1b94 and 489323a5): the folders
// below and including the given ones whose subtree holds no file, deepest
// first, so each is empty when its turn comes. Never the scan root, a mount
// point, a folder that could not be read, anything reached through a
// symlink (checked on disk), or on macOS a package (an app, a Photos
// library) or what is inside one, unless that package was selected.
+ (NSArray *)emptyFoldersIn:(NSArray *)nodes rootNode:(LDFileNode *)root;
// Change Folder Dates: every real folder in and below the given nodes (the
// whole tree when none are given), never through a symlink or into a macOS
// package that was not selected, with a known last change.
+ (NSArray *)foldersForDatesIn:(NSArray *)nodes rootNode:(LDFileNode *)root;

// The folders a terminal opens in: each folder itself, a file's parent,
// without repeats.
+ (NSArray *)folderNodesForNodes:(NSArray *)nodes;

// YES for the synthetic "This Computer" root of a multi-volume scan.
+ (BOOL)isComputerNode:(LDFileNode *)node;
// Scan roots and the mount points shown in the tree ("drives").
+ (BOOL)isVolumeNode:(LDFileNode *)node rootNode:(LDFileNode *)root;

@end
