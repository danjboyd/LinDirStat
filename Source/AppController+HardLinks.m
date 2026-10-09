#import "AppController.h"
#import "AppController+Private.h"
#import "LDHardLinks.h"
#import "LDPreferences.h"
#import "LDScanSession.h"
#import "LDSizeFormatter.h"
#import "LDTreemapView.h"

// WinDirStat's hard-link display in the directory tree (FileTreeControl.cpp):
// a link shows "⧉ <size>" in Physical Size and a reference under
// "<Hardlinks>" shows "⫘ <size>". Clicking either jumps to the other side:
// from a link to its file's Index folder, from a reference to the link.
@implementation AppController (HardLinks)

- (LDHardLinkTable *)hardLinkTable
{
  return [LDHardLinkTable tableForRoot:_rootNode];
}

- (NSString *)physicalSizeStringForNode:(LDFileNode *)node
{
  if ([node isHardLink]) {
    LDHardLinkSet *set = [[self hardLinkTable] setForNode:node];
    return [@"⧉ " stringByAppendingString:[LDSizeFormatter stringForBytes:set ? [set allocatedSize] : [node allocatedSize]]];
  }
  if (LDHardLinkItemTypeOfNode(node) == LDHardLinkItemReference) {
    return [@"⫘ " stringByAppendingString:[LDSizeFormatter stringForBytes:[node allocatedSize]]];
  }
  return [LDSizeFormatter stringForBytes:[node aggregateAllocatedSize]];
}

// A link's own logical size, as WinDirStat shows it, although its folders
// count it under "<Hardlinks>".
- (NSString *)logicalSizeStringForNode:(LDFileNode *)node
{
  LDHardLinkSet *set = [node isHardLink] ? [[self hardLinkTable] setForNode:node] : nil;
  return [LDSizeFormatter stringForBytes:set ? [set size] : [node aggregateSize]];
}

- (BOOL)listView:(NSTableView *)view hasLinkAtRow:(NSInteger)row column:(NSInteger)column
{
  if (view != (NSTableView *)_directoryTable || row < 0 || column < 0 || column >= (NSInteger)[[view tableColumns] count]) {
    return NO;
  }
  if (![[[[view tableColumns] objectAtIndex:(NSUInteger)column] identifier] isEqualToString:LDColumnPhysicalSize]) {
    return NO;
  }
  LDFileNode *node = [_directoryTable itemAtRow:row];
  return [node isHardLink] || LDHardLinkItemTypeOfNode(node) == LDHardLinkItemReference;
}

- (void)listView:(NSTableView *)view followLinkAtRow:(NSInteger)row column:(NSInteger)column
{
  if (![self listView:view hasLinkAtRow:row column:column]) {
    return;
  }
  LDFileNode *node = [_directoryTable itemAtRow:row];
  LDFileNode *target = [node isHardLink] ? [LDHardLinks indexNodeForLink:node] : [LDHardLinks linkForReference:node];
  if (!target || ![_rootNode isAncestorOf:target]) {
    return;
  }
  [self revealNodeInTree:target];
  if (LDHardLinkItemTypeOfNode(target) == LDHardLinkItemIndex) {
    [_directoryTable expandItem:target];
  }
  [_treemapView setSelectedNode:target];
  [self showStatus:[self describeNode:target]];
  [self updateSelectionField];
  [self refreshCommandState];
}

// Refresh Selected keeps the scan's hard-link table: the rescan of node does
// not count again files whose other links are outside it.
- (void)prepareRefreshSession:(LDScanSession *)session ofNode:(LDFileNode *)node
{
  [session setHardLinkTable:[self hardLinkTable] replacing:node];
}

// After node was replaced (by replacement, or removed): forgets its links,
// moves the bytes of files it held the counted link of to a remaining link,
// and brings "<Hardlinks>" and the totals in line.
- (void)updateHardLinksAfterReplacing:(LDFileNode *)node withNode:(LDFileNode *)replacement canceled:(BOOL)canceled
{
  LDHardLinkTable *table = [self hardLinkTable];
  if (!table) {
    return;
  }
  NSMutableArray *folders = [NSMutableArray array];
  // A canceled refresh keeps node; the links its partial rescan found go.
  for (LDFileNode *heir in [table removeLinksUnder:canceled ? replacement : node]) {
    if ([heir parent]) {
      [folders addObject:[heir parent]];
    }
  }
  [folders addObjectsFromArray:[LDHardLinks updateTree:_rootNode table:table metric:_sizeMetric retiring:nil]];
  for (LDFileNode *folder in folders) {
    if ([_rootNode isAncestorOf:folder]) {
      [folder updateTotalsUpwardSortedByMetric:_sizeMetric];
    }
  }
}

@end
