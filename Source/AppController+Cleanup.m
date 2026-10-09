#import "AppController.h"
#import "AppController+Private.h"
#import "LDCommandRules.h"
#import "LDCustomCleanupRunner.h"
#import "LDDesktop.h"
#import "LDDialogs.h"
#import "LDFileOperations.h"
#import "LDPreferences.h"
#import "LDScanSession.h"
#import "LDSizeFormatter.h"
#import "LDTreemapView.h"

// WinDirStat's Clean Up commands (DirStatDoc.cpp), acting on the selection
// of the focused file list. After anything that changes the disk, the
// affected items are refreshed: rescanned in place, or removed from the tree
// when they are gone (WinDirStat's StartScanningEngine).
@implementation AppController (Cleanup)

#pragma mark - Selection

- (NSString *)stringForPathData:(NSData *)pathData
{
  return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:[pathData bytes] length:[pathData length]];
}

- (NSArray *)displayPathsForNodes:(NSArray *)nodes
{
  NSMutableArray *paths = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    [paths addObject:[node path]];
  }
  return paths;
}

- (BOOL)selectionAllows:(LDCommand)command
{
  return [LDCommandRules isCommand:command enabledForNodes:[self selectedNodes] rootNode:_rootNode busy:[self isBusy]];
}

#pragma mark - Open, reveal, terminal, properties

- (void)openItem:(id)sender
{
  (void)sender;
  if (![self selectionAllows:LDCommandOpen]) {
    return;
  }
  for (LDFileNode *node in [self selectedNodes]) {
    NSString *path = [node path];
    [LDDesktop runFirstSuccessfulCommand:[LDDesktop openCommandsForPath:[node pathData]]
                             inDirectory:nil
                              completion:^(BOOL succeeded) {
      if (!succeeded) {
        [self showStatus:[NSString stringWithFormat:@"No application could open %@", [self displayPath:path]]];
      }
    }];
  }
}

- (void)revealItem:(id)sender
{
  (void)sender;
  if (![self selectionAllows:LDCommandReveal]) {
    return;
  }
  for (LDFileNode *node in [self selectedNodes]) {
    [LDDesktop runFirstSuccessfulCommand:[LDDesktop revealCommandsForPath:[node pathData]] inDirectory:nil completion:nil];
  }
}

- (void)openTerminal:(id)sender
{
  (void)sender;
  if (![self selectionAllows:LDCommandTerminal]) {
    return;
  }
  for (LDFileNode *folder in [LDCommandRules folderNodesForNodes:[self selectedNodes]]) {
    NSData *directory = [folder pathData];
    if (![LDDesktop launchFirstAvailableCommand:[LDDesktop terminalCommandsForDirectory:directory] inDirectory:directory]) {
      [self showStatus:@"No terminal application was found"];
      return;
    }
  }
}

- (void)showProperties:(id)sender
{
  (void)sender;
  if (![self selectionAllows:LDCommandProperties]) {
    return;
  }
  for (LDFileNode *node in [self selectedNodes]) {
    [LDDialogs showPropertiesForNode:node];
  }
}

- (void)copyPath:(id)sender
{
  (void)sender;
  NSArray *nodes = [self selectedNodes];
  if (![self selectionAllows:LDCommandCopyPath]) {
    return;
  }
  NSString *text = [[self displayPathsForNodes:nodes] componentsJoinedByString:@"\n"];
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
  [pasteboard declareTypes:@[NSStringPboardType] owner:nil];
  [pasteboard setString:text forType:NSStringPboardType];
  [self showStatus:[nodes count] == 1
    ? [NSString stringWithFormat:@"Copied %@", [self displayPath:[[nodes objectAtIndex:0] path]]]
    : [NSString stringWithFormat:@"Copied %lu paths", (unsigned long)[nodes count]]];
}

#pragma mark - Delete, trash, empty folder, move

- (BOOL)confirmAction:(NSString *)action message:(NSString *)message paths:(NSArray *)paths
{
  LDPreferences *preferences = [LDPreferences sharedPreferences];
  if (![preferences showDeleteWarning]) {
    return YES;
  }
  BOOL dontAskAgain = NO;
  BOOL confirmed = [LDDialogs confirmDestructiveAction:action message:message paths:paths dontAskAgain:&dontAskAgain];
  if (confirmed && dontAskAgain) {
    [preferences setShowDeleteWarning:NO];
  }
  return confirmed;
}

// Runs operation on each path in the background, then reports failures and
// refreshes the given nodes.
- (void)performFileOperation:(NSString *)verb
                       paths:(NSArray *)paths
                   operation:(BOOL (^)(NSData *path, NSError **error))operation
              thenRefreshing:(NSArray *)refreshNodes
{
  _fileOperationRunning = YES;
  [self startBusyIndicator];
  [self showStatus:[NSString stringWithFormat:@"%@…", verb]];
  [self refreshCommandState];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSMutableArray *failures = [NSMutableArray array];
    for (NSData *path in paths) {
      NSError *error = nil;
      if (!operation(path, &error)) {
        [failures addObject:[NSString stringWithFormat:@"%@: %@", [self stringForPathData:path], [error localizedDescription]]];
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      _fileOperationRunning = NO;
      if ([failures count] > 0) {
        [LDDialogs showFailures:failures title:[NSString stringWithFormat:@"%@ failed for %lu items", verb, (unsigned long)[failures count]]];
      }
      [self refreshNodes:refreshNodes];
    });
  });
}

- (void)deleteNodes:(NSArray *)selection permanently:(BOOL)permanently
{
  LDCommand command = permanently ? LDCommandDeletePermanently : LDCommandMoveToTrash;
  if (![LDCommandRules isCommand:command enabledForNodes:selection rootNode:_rootNode busy:[self isBusy]]) {
    return;
  }
  NSArray *nodes = [LDCommandRules topmostNodes:selection];
  NSString *action = permanently ? @"Delete Permanently" : @"Move to Trash";
  NSString *message = permanently
    ? @"These items will be deleted permanently. They cannot be recovered."
    : @"These items will be moved to the trash.";
  if (![self confirmAction:action message:message paths:[self displayPathsForNodes:nodes]]) {
    return;
  }
  NSMutableArray *paths = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    [paths addObject:[node pathData]];
  }
  NSMutableArray *refresh = [nodes mutableCopy];
  if (!permanently) {
    // Like WinDirStat's recycler folders: a trash inside the tree grows.
    for (NSData *trash in [LDFileOperations existingTrashDirectories]) {
      LDFileNode *trashNode = [self nodeForPathData:trash];
      if (trashNode) {
        [refresh addObject:trashNode];
      }
    }
  }
  [self performFileOperation:permanently ? @"Deleting" : @"Moving to the trash"
                       paths:paths
                   operation:^BOOL(NSData *path, NSError **error) {
    return permanently ? [LDFileOperations deletePermanently:path error:error]
                       : [LDFileOperations moveToTrash:path error:error];
  }
              thenRefreshing:refresh];
}

- (void)moveToTrash:(id)sender
{
  (void)sender;
  [self deleteNodes:[self selectedNodes] permanently:NO];
}

- (void)deletePermanently:(id)sender
{
  (void)sender;
  [self deleteNodes:[self selectedNodes] permanently:YES];
}

- (void)emptyFolder:(id)sender
{
  (void)sender;
  if (![self selectionAllows:LDCommandEmptyFolder]) {
    return;
  }
  NSArray *folders = [LDCommandRules topmostNodes:[self selectedNodes]];
  if (![self confirmAction:@"Empty Folder"
                   message:@"Everything inside these folders will be deleted permanently. The folders themselves are kept."
                     paths:[self displayPathsForNodes:folders]]) {
    return;
  }
  NSMutableArray *paths = [NSMutableArray array];
  for (LDFileNode *folder in folders) {
    for (LDFileNode *child in [folder children]) {
      [paths addObject:[child pathData]];
    }
  }
  [self performFileOperation:@"Emptying folders"
                       paths:paths
                   operation:^BOOL(NSData *path, NSError **error) {
    return [LDFileOperations deletePermanently:path error:error];
  }
              thenRefreshing:folders];
}

- (void)moveItemsTo:(id)sender
{
  (void)sender;
  if (![self selectionAllows:LDCommandMoveTo]) {
    return;
  }
  NSArray *nodes = [LDCommandRules topmostNodes:[self selectedNodes]];
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setTitle:@"Move To"];
  [panel setPrompt:@"Move"];
  [panel setCanChooseFiles:NO];
  [panel setCanChooseDirectories:YES];
  [panel setAllowsMultipleSelection:NO];
  NSInteger result = [panel runModalForDirectory:[[(LDFileNode *)[nodes objectAtIndex:0] parent] path] file:nil types:nil];
  if (result != NSFileHandlingPanelOKButton && result != NSOKButton) {
    return;
  }
  NSString *destination = [self selectedDirectoryPathFromOpenPanel:panel];
  if ([destination length] == 0) {
    return;
  }
  const char *destinationBytes = [destination fileSystemRepresentation];
  NSData *destinationData = [NSData dataWithBytes:destinationBytes length:strlen(destinationBytes)];
  NSMutableArray *paths = [NSMutableArray array];
  NSMutableArray *refresh = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    [paths addObject:[node pathData]];
    if ([refresh indexOfObjectIdenticalTo:[node parent]] == NSNotFound) {
      [refresh addObject:[node parent]];
    }
  }
  LDFileNode *destinationNode = [self nodeForPathData:destinationData];
  if (destinationNode) {
    [refresh addObject:destinationNode];
  }
  [self performFileOperation:@"Moving"
                       paths:paths
                   operation:^BOOL(NSData *path, NSError **error) {
    return [LDFileOperations moveItem:path toDirectory:destinationData error:error];
  }
              thenRefreshing:refresh];
}

- (void)emptyTrash:(id)sender
{
  (void)sender;
  NSArray *trashes = [LDFileOperations existingTrashDirectories];
  if ([trashes count] == 0) {
    [self showStatus:@"The trash is already empty"];
    return;
  }
  NSMutableArray *paths = [NSMutableArray array];
  for (NSData *trash in trashes) {
    [paths addObject:[self stringForPathData:trash]];
  }
  if (![self confirmAction:@"Empty Trash" message:@"Everything in these trash folders will be deleted permanently." paths:paths]) {
    return;
  }
  NSMutableArray *refresh = [NSMutableArray array];
  for (NSData *trash in trashes) {
    LDFileNode *trashNode = [self nodeForPathData:trash];
    if (trashNode) {
      [refresh addObject:trashNode];
    }
  }
  [self performFileOperation:@"Emptying the trash"
                       paths:@[[NSNull null]]
                   operation:^BOOL(NSData *unused, NSError **error) {
    (void)unused;
    return [LDFileOperations emptyTrashDirectories:trashes error:error];
  }
              thenRefreshing:refresh];
}

#pragma mark - Custom cleanups

- (void)runCustomCleanup:(id)sender
{
  NSUInteger slot = (NSUInteger)[sender tag];
  NSArray *cleanups = [[LDPreferences sharedPreferences] customCleanups];
  if (slot >= [cleanups count]) {
    return;
  }
  LDCustomCleanup *cleanup = [cleanups objectAtIndex:slot];
  NSArray *nodes = [self selectedNodes];
  if (![LDCommandRules isCleanup:cleanup enabledForNodes:nodes rootNode:_rootNode busy:[self isBusy]]) {
    return;
  }
  NSString *title = [cleanup displayTitleForSlot:slot];
  NSMutableArray *chosen = [NSMutableArray array];
  for (LDFileNode *node in nodes) {
    if ([cleanup askForConfirmation]) {
      NSString *message = [NSString stringWithFormat:@"You are about to run the %@custom cleanup “%@” on “%@”. Continue?",
                           [cleanup recurseIntoSubdirectories] ? @"recursive " : @"", title, [node path]];
      NSInteger choice = [LDDialogs runListPanelWithTitle:title message:message items:nil
                                                  buttons:@[@"Skip", @"Run"] defaultIndex:1
                                            checkboxTitle:nil checked:NULL];
      if (choice != 1) {
        continue;
      }
    }
    [chosen addObject:node];
  }
  if ([chosen count] == 0) {
    return;
  }

  NSMutableArray *paths = [NSMutableArray array];
  NSMutableArray *directories = [NSMutableArray array];
  NSMutableArray *refresh = [NSMutableArray array];
  for (LDFileNode *node in chosen) {
    [paths addObject:[node pathData]];
    [directories addObject:@([node kind] == LDFileNodeKindDirectory)];
    LDFileNode *target = nil;
    if ([cleanup refreshPolicy] == LDRefreshPolicyEntry) {
      target = node;
    } else if ([cleanup refreshPolicy] == LDRefreshPolicyParent) {
      target = [node parent] ?: node;
    }
    if (target && [refresh indexOfObjectIdenticalTo:target] == NSNotFound) {
      [refresh addObject:target];
    }
  }
  BOOL waits = [cleanup waitForCompletion] || [cleanup recurseIntoSubdirectories];
  if (waits) {
    _fileOperationRunning = YES;
    [self startBusyIndicator];
    [self refreshCommandState];
  }
  [self showStatus:[NSString stringWithFormat:@"Running %@…", title]];
  [LDCustomCleanupRunner runCleanup:cleanup onPaths:paths directories:directories completion:^(NSArray *ranPaths, NSArray *failures) {
    (void)ranPaths;
    _fileOperationRunning = NO;
    if ([failures count] > 0) {
      NSMutableArray *lines = [NSMutableArray array];
      for (NSData *path in failures) {
        [lines addObject:[self stringForPathData:path]];
      }
      [LDDialogs showFailures:lines title:[NSString stringWithFormat:@"%@ failed", title]];
    }
    if (waits) {
      [self refreshNodes:refresh];
    } else {
      [self finishBusyWork];
    }
  }];
}

- (NSMenu *)customCleanupMenu
{
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Custom Cleanup"];
  NSArray *cleanups = [[LDPreferences sharedPreferences] customCleanups];
  for (NSUInteger slot = 0; slot < [cleanups count]; slot++) {
    LDCustomCleanup *cleanup = [cleanups objectAtIndex:slot];
    if (![cleanup isEnabled]) {
      continue;
    }
    NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:[cleanup displayTitleForSlot:slot]
                                       action:@selector(runCustomCleanup:)
                                keyEquivalent:[NSString stringWithFormat:@"%lu", (unsigned long)slot]];
    [item setTarget:self];
    [item setTag:(NSInteger)slot];
  }
  if ([menu numberOfItems] == 0) {
    NSMenuItem *none = (NSMenuItem *)[menu addItemWithTitle:@"No Custom Cleanups — Set Them Up in Preferences" action:NULL keyEquivalent:@""];
    [none setEnabled:NO];
  }
  return menu;
}

#pragma mark - Refresh

- (void)refreshSelected:(id)sender
{
  (void)sender;
  if (![self selectionAllows:LDCommandRefreshSelected]) {
    return;
  }
  [self refreshNodes:[self selectedNodes]];
}

// Finds the node for an exact path, if it is in the tree.
- (LDFileNode *)nodeForPathData:(NSData *)pathData
{
  if (!_rootNode || [pathData length] == 0) {
    return nil;
  }
  NSMutableArray *roots = [NSMutableArray array];
  if ([LDCommandRules isComputerNode:_rootNode]) {
    [roots addObjectsFromArray:[_rootNode children]];
  } else {
    [roots addObject:_rootNode];
  }
  for (LDFileNode *root in roots) {
    NSData *rootPath = [root pathData];
    NSUInteger rootLength = [rootPath length];
    if ([pathData length] < rootLength || memcmp([pathData bytes], [rootPath bytes], rootLength) != 0) {
      continue;
    }
    const char *bytes = [pathData bytes];
    NSUInteger position = rootLength;
    if (position < [pathData length] && bytes[position] != '/' && !(rootLength == 1 && bytes[0] == '/')) {
      continue;
    }
    LDFileNode *cursor = root;
    while (cursor && position < [pathData length]) {
      while (position < [pathData length] && bytes[position] == '/') {
        position++;
      }
      NSUInteger end = position;
      while (end < [pathData length] && bytes[end] != '/') {
        end++;
      }
      if (end == position) {
        break;
      }
      LDFileNode *next = nil;
      for (LDFileNode *child in [cursor children]) {
        const char *name = [child nameBytes];
        if (strlen(name) == end - position && memcmp(name, bytes + position, end - position) == 0) {
          next = child;
          break;
        }
      }
      cursor = next;
      position = end;
    }
    if (cursor) {
      return cursor;
    }
  }
  return nil;
}

- (void)refreshNodes:(NSArray *)nodes
{
  NSMutableArray *targets = [NSMutableArray array];
  for (LDFileNode *node in [LDCommandRules topmostNodes:nodes]) {
    // The root (or "This Computer") is refreshed by scanning it again.
    if (node == _rootNode || ![node parent] || [LDCommandRules isComputerNode:node]) {
      [self finishBusyWork];
      [self rescan:nil];
      return;
    }
    [targets addObject:node];
  }
  if ([targets count] == 0) {
    [self finishBusyWork];
    return;
  }
  _refreshQueue = targets;
  [self startBusyIndicator];
  [self refreshCommandState];
  [self refreshNextNode];
}

- (void)refreshNextNode
{
  LDFileNode *node = [_refreshQueue firstObject];
  if (!node) {
    _refreshQueue = nil;
    _refreshSession = nil;
    [self didChangeTree];
    [self finishBusyWork];
    return;
  }
  [_refreshQueue removeObjectAtIndex:0];
  // A node removed by an earlier refresh in this batch is skipped.
  if (![_rootNode isAncestorOf:node]) {
    [self refreshNextNode];
    return;
  }
  if ([node kind] == LDFileNodeKindDirectory) {
    [(LDDirectoryNode *)node beginPendingScans:1];
  }
  [self showStatus:[NSString stringWithFormat:@"Refreshing %@…", [self displayPath:[node path]]]];
  LDScanSession *session = [[LDScanSession alloc] init];
  [self configureScanSession:session];
  _refreshSession = session;
  [session startAsyncRefreshOfPathData:[node pathData] completion:^(LDFileNode *replacement) {
    if (session != _refreshSession) {
      return;
    }
    [self replaceNode:node withNode:[session isCanceled] ? nil : replacement keepIfCanceled:[session isCanceled]];
    [self refreshNextNode];
  }];
}

- (void)replaceNode:(LDFileNode *)node withNode:(LDFileNode *)replacement keepIfCanceled:(BOOL)canceled
{
  LDDirectoryNode *parent = (LDDirectoryNode *)[node parent];
  if ([node kind] == LDFileNodeKindDirectory) {
    [(LDDirectoryNode *)node clearPendingScans];
  }
  if (!parent || canceled) {
    return;
  }
  // Parent pointers do not retain, and the file lists may still hold nodes
  // below node until they are rebuilt, so the old subtree is kept until the
  // next scan.
  [_detachedSubtrees addObject:node];
  if (replacement) {
    [parent replaceChild:node withNode:replacement];
  } else {
    [parent removeChild:node];
  }
  [parent updateTotalsUpwardSortedByMetric:_sizeMetric];
  [self forgetNode:node replacement:replacement];
}

@end
